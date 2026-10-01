public import AppKit
public import AtelierTextRendering
import QuartzCore

/// The renderer's `@MainActor` host view (text-renderer.md §3.4-3.6): rows as `CALayer` tiles of
/// ``rowsPerTile`` rows, the height index kept live and corrected as tiles land, and the geometry a backend-neutral
/// gutter, minimap or hover needs.
///
/// M1 keeps the scheduling simple: one child task renders each dirty tile (``AtelierTextRendering/TextTypesetter/render(_:of:decorations:configuration:appearance:colorSpace:scale:)``),
/// and geometry queries small enough to answer inline call the synchronous typesetting core
/// (``AtelierTextRendering/TextTypesetter/layoutSynchronously(_:of:configuration:)``) directly from the main actor.
/// The full background pipeline of §3.4 — a bounded task group, a generation counter dropping stale results,
/// screen-ahead prefetch, an LRU tile and row-geometry cache — is a follow-up; this host never keeps more than the
/// tiles near the viewport, but does not yet bound that by bytes.
@MainActor
public final class TextCanvasView: NSView {
    /// Rows per tile (text-renderer.md §3.5).
    public static let rowsPerTile = 32

    public private(set) var text: StyledText
    public var configuration: LayoutConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            invalidateAllTiles()
            rebuildHeightIndex()
            needsLayout = true
        }
    }
    public var renderAppearance: Appearance = .light {
        didSet {
            guard renderAppearance != oldValue else { return }
            invalidateAllTiles()
            updateTiles()
        }
    }
    /// Whether ``configuration``'s wrap width tracks this view's own width, as a pane wrapping at the viewport does.
    public var tracksViewportWidth = false {
        didSet {
            guard tracksViewportWidth else { return }
            configuration.wrap = .width(bounds.width)
        }
    }
    /// Space above the first row, matching a host's own container inset so a gutter beside this view lines up with
    /// one beside a different backend's text system.
    public var topInset: Double = 0 {
        didSet {
            guard topInset != oldValue else { return }
            invalidateIntrinsicContentSize()
            setFrameSize(NSSize(width: max(bounds.width, 1), height: max(documentHeight, 1)))
            updateTiles()
        }
    }

    private var heightIndex: HeightIndex
    private var decorations: [DecorationLayer] = []
    private var generation = 0
    private var tileLayers: [Int: CALayer] = [:]
    private var pendingTasks: [Int: Task<Void, Never>] = [:]
    /// Per-row geometry, kept only for rows a tile has typeset; cleared on any change that invalidates it.
    private var geometryCache: [Int: RowGeometry] = [:]

    public init(configuration: LayoutConfiguration) {
        self.configuration = configuration
        text = .plain(rows: [[UInt8]](), font: FontSpec(pointSize: 12), plainStyle: Self.defaultStyle)
        heightIndex = HeightIndex(text: text, configuration: configuration, cellAdvance: 8)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override var isFlipped: Bool { true }

    private static let defaultStyle = TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))

    /// Shows `text`; the pane starts at its top (M1: `keepingAnchor` is not yet honoured — a follow-up needs the
    /// scroll-anchoring of text-renderer.md §3.3).
    public func show(_ text: StyledText, keepingAnchor: Bool) {
        self.text = text
        invalidateAllTiles()
        rebuildHeightIndex()
        invalidateIntrinsicContentSize()
        setFrameSize(NSSize(width: max(bounds.width, 1), height: max(documentHeight, 1)))
        needsLayout = true
        updateTiles()
    }

    /// Shows `layer` over the text, replacing any layer already carrying `layer.id`. M1 redraws every tile now
    /// materialized rather than only the rows `layer` changed (text-renderer.md §3.2's "affected tiles only" is a
    /// follow-up).
    public func setDecorations(_ layer: DecorationLayer) {
        if let index = decorations.firstIndex(where: { $0.id == layer.id }) {
            decorations[index] = layer
        } else {
            decorations.append(layer)
        }
        generation += 1
        for task in pendingTasks.values { task.cancel() }
        pendingTasks.removeAll()
        for tileLayer in tileLayers.values { tileLayer.contents = nil }
        updateTiles()
    }

    public var documentHeight: Double { heightIndex.documentHeight + topInset }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: documentHeight)
    }

    /// Rows intersecting `rect`, top to bottom, with each row's frame and its first line's baseline, in this view's
    /// own coordinates (``topInset`` above the first row). Never lays out rows outside `rect`, beyond the one it may
    /// type set to answer a row still estimated.
    public func forEachRow(in rect: CGRect, _ body: (_ row: RowIndex, _ frame: CGRect, _ baseline: Double) -> Void) {
        guard text.rowCount > 0 else { return }
        var row = heightIndex.row(atY: rect.minY - topInset)
        while row.index < text.rowCount {
            let top = heightIndex.y(of: row) + topInset
            if top > rect.maxY { break }
            let geometry = rowGeometry(of: row)
            let frame = CGRect(x: 0, y: top, width: bounds.width, height: Double(geometry.height))
            if frame.maxY >= rect.minY {
                body(row, frame, top + Double(geometry.lines.first?.baseline ?? 0))
            }
            row = row.advanced(by: 1)
        }
    }

    /// The rows intersecting the pane's visible rect (its enclosing scroll view's clip view, or its own bounds when
    /// it has none, as an embedded pane does).
    public func visibleRowRange() -> Range<RowIndex> {
        guard text.rowCount > 0 else { return RowIndex(0) ..< RowIndex(0) }
        let rect = visibleDocumentRect().offsetBy(dx: 0, dy: -topInset)
        let first = heightIndex.row(atY: rect.minY)
        let last = heightIndex.row(atY: max(rect.maxY - 1, rect.minY))
        return first ..< RowIndex(last.index + 1)
    }

    /// `row`'s own frame and first-line baseline, type setting it first if its height is still estimated.
    public func frame(ofRow row: RowIndex) -> (frame: CGRect, baseline: Double)? {
        guard row.index >= 0, row.index < text.rowCount else { return nil }
        let top = heightIndex.y(of: row) + topInset
        let geometry = rowGeometry(of: row)
        let frame = CGRect(x: 0, y: top, width: bounds.width, height: Double(geometry.height))
        return (frame, top + Double(geometry.lines.first?.baseline ?? 0))
    }

    /// Heights of every row, and whether they are all exact (``AtelierTextRendering/HeightIndex/isExact(_:)``), for
    /// split alignment.
    public func rowHeights() -> (heights: [Double], isExact: Bool) {
        var heights: [Double] = []
        heights.reserveCapacity(text.rowCount)
        var isExact = true
        for index in 0 ..< text.rowCount {
            let row = RowIndex(index)
            heights.append(Double(heightIndex.height(of: row)))
            isExact = isExact && heightIndex.isExact(row)
        }
        return (heights, isExact)
    }

    /// Brings `row` into view: near the top, or centred.
    public func scroll(toRow row: RowIndex, centered: Bool) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let top = heightIndex.y(of: row) + topInset
        let target: Double =
            if centered {
                max(top - (clipView.bounds.height - Double(rowGeometry(of: row).height)) / 2, 0)
            } else {
                max(top - 3 * configuration.resolvedLineHeight, 0)
            }
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: target))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        updateTiles()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrolling()
        updateAppearance()
        updateTiles()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        renderAppearance = isDark ? .dark : .light
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged, tracksViewportWidth {
            configuration.wrap = .width(newSize.width)
        }
        updateTiles()
    }

    // MARK: Scrolling and tiling

    private func observeScrolling() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clipView)
    }

    @objc private func scrolled() {
        updateTiles()
    }

    private func visibleDocumentRect() -> CGRect {
        enclosingScrollView?.contentView.bounds ?? bounds
    }

    private func rebuildHeightIndex() {
        heightIndex = HeightIndex(text: text, configuration: configuration, cellAdvance: currentCellAdvance())
    }

    private func currentCellAdvance() -> Double {
        Double(("0" as NSString).size(withAttributes: [.font: Self.font(for: text.styles.font)]).width)
    }

    private static func font(for spec: FontSpec) -> NSFont {
        if let name = spec.postScriptName, let font = NSFont(name: name, size: spec.pointSize) { return font }
        return .monospacedSystemFont(ofSize: spec.pointSize, weight: .regular)
    }

    /// `row`'s geometry, type setting it once if its height is still estimated, and correcting the height index.
    private func rowGeometry(of row: RowIndex) -> RowGeometry {
        if heightIndex.isExact(row), let cached = geometryCache[row.index] { return cached }
        guard
            let geometry =
                try? TextTypesetter.layoutSynchronously(
                    row ..< row.advanced(by: 1), of: text, configuration: configuration
                )
                .first
        else { return RowGeometry(height: Float(configuration.resolvedLineHeight), lines: []) }
        if !heightIndex.isExact(row) || heightIndex.height(of: row) != geometry.height {
            _ = heightIndex.setHeight(geometry.height, of: row)
        }
        geometryCache[row.index] = geometry
        return geometry
    }

    private func invalidateAllTiles() {
        generation += 1
        geometryCache.removeAll()
        for task in pendingTasks.values { task.cancel() }
        pendingTasks.removeAll()
        for tileLayer in tileLayers.values { tileLayer.removeFromSuperlayer() }
        tileLayers.removeAll()
    }

    private func tileRange(forTile index: Int) -> Range<Int> {
        let start = index * Self.rowsPerTile
        let end = min(start + Self.rowsPerTile, text.rowCount)
        return start ..< max(end, start)
    }

    private func tileLayer(for index: Int) -> CALayer {
        if let existing = tileLayers[index] { return existing }
        let tileLayer = CALayer()
        tileLayer.anchorPoint = .zero
        tileLayer.contentsGravity = .topLeft
        layer?.addSublayer(tileLayer)
        tileLayers[index] = tileLayer
        return tileLayer
    }

    private func positionTile(_ tileLayer: CALayer, index: Int) {
        let rows = tileRange(forTile: index)
        guard !rows.isEmpty else { return }
        let top = heightIndex.y(of: RowIndex(rows.lowerBound)) + topInset
        let bottom =
            rows.upperBound < text.rowCount ? heightIndex.y(of: RowIndex(rows.upperBound)) + topInset : documentHeight
        tileLayer.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(bottom - top, 1))
    }

    /// Materializes the tiles near the viewport and discards the rest.
    private func updateTiles() {
        guard text.rowCount > 0, bounds.width > 0 else { return }
        let visible = visibleDocumentRect().offsetBy(dx: 0, dy: -topInset)
        let firstRow = heightIndex.row(atY: visible.minY)
        let lastRow = heightIndex.row(atY: max(visible.maxY - 1, visible.minY))
        let lastTileIndex = max(text.rowCount - 1, 0) / Self.rowsPerTile
        let firstTile = max(firstRow.index / Self.rowsPerTile - 1, 0)
        let lastTile = min(lastRow.index / Self.rowsPerTile + 1, lastTileIndex)
        guard firstTile <= lastTile else { return }
        let wanted = Set(firstTile ... lastTile)
        for index in tileLayers.keys where !wanted.contains(index) {
            tileLayers[index]?.removeFromSuperlayer()
            tileLayers.removeValue(forKey: index)
            pendingTasks[index]?.cancel()
            pendingTasks.removeValue(forKey: index)
        }
        for index in wanted {
            let tileLayer = tileLayer(for: index)
            positionTile(tileLayer, index: index)
            if tileLayer.contents == nil, pendingTasks[index] == nil {
                renderTile(index: index)
            }
        }
    }

    private func renderTile(index: Int) {
        let rows = tileRange(forTile: index)
        guard !rows.isEmpty else { return }
        let currentGeneration = generation
        let snapshot = text
        let decorationsSnapshot = decorations
        let snapshotConfiguration = configuration
        let snapshotAppearance = renderAppearance
        // A follow-up: the window's own colour space (text-renderer.md §3.5); sRGB is correct, if costlier to commit.
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let scale = Double(window?.backingScaleFactor ?? 2)
        pendingTasks[index] = Task { [weak self] in
            guard
                let tile = try? await TextTypesetter.render(
                    RowIndex(rows.lowerBound) ..< RowIndex(rows.upperBound), of: snapshot,
                    decorations: decorationsSnapshot, configuration: snapshotConfiguration,
                    appearance: snapshotAppearance, colorSpace: colorSpace, scale: scale)
            else { return }
            self?.apply(tile: tile, tileIndex: index, generation: currentGeneration)
        }
    }

    private func apply(tile: RenderedTile, tileIndex: Int, generation: Int) {
        pendingTasks.removeValue(forKey: tileIndex)
        guard generation == self.generation, let tileLayer = tileLayers[tileIndex] else { return }
        var corrected = false
        for (offset, geometry) in tile.geometry.enumerated() {
            let row = RowIndex(tile.rows.lowerBound.rawValue + Int32(offset))
            geometryCache[row.index] = geometry
            if !heightIndex.isExact(row) || heightIndex.height(of: row) != geometry.height {
                _ = heightIndex.setHeight(geometry.height, of: row)
                corrected = true
            }
        }
        tileLayer.contents = tile.image
        tileLayer.contentsScale = window?.backingScaleFactor ?? 2
        if corrected {
            invalidateIntrinsicContentSize()
            setFrameSize(NSSize(width: bounds.width, height: max(documentHeight, 1)))
            for (index, layer) in tileLayers { positionTile(layer, index: index) }
        } else {
            positionTile(tileLayer, index: tileIndex)
        }
    }
}
