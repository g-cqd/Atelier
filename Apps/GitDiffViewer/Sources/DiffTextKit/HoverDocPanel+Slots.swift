import AppKit
import DiffRendering
import Foundation
import os

// Slot rendering, measurement and view factories; apart from HoverDocPanel.swift, to keep it within the
// limits SwiftLint sets.
extension HoverDocPanel {
    func renderParameters(_ parameters: [HoverDocument.Field]) {
        while parametersGrid.numberOfRows > 0 {
            let row = parametersGrid.row(at: parametersGrid.numberOfRows - 1)
            // Removing a row leaves its cells' views in the grid, unplaced: they go with it.
            let views = (0 ..< row.numberOfCells).compactMap { row.cell(at: $0).contentView }
            parametersGrid.removeRow(at: parametersGrid.numberOfRows - 1)
            views.forEach { $0.removeFromSuperview() }
        }
        let nameLabels = parameters.map { parameter in
            let label = NSTextField(labelWithString: parameter.name)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .labelColor
            return label
        }
        let nameColumnWidth = nameLabels.map { ceil($0.intrinsicContentSize.width) }.max() ?? 0
        // The descriptions wrap at the width their column has once the names take theirs, so their height counts
        // every line they are laid out on.
        let textColumnWidth =
            HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset - nameColumnWidth - parametersGrid.columnSpacing
        for (parameter, nameLabel) in zip(parameters, nameLabels) {
            let textLabel = NSTextField(labelWithAttributedString: parameter.text)
            textLabel.lineBreakMode = .byWordWrapping
            textLabel.preferredMaxLayoutWidth = max(textColumnWidth, 1)
            parametersGrid.addRow(with: [nameLabel, textLabel])
        }
        // The names' column is as wide as the widest name, and the text's takes the rest of the grid's width: sized
        // to their content alone, the two columns would share that rest in no set way.
        parametersGrid.column(at: 0).width = parameters.isEmpty ? NSGridView.sizedForContent : nameColumnWidth
    }

    /// Rebuilds the candidates group: a chip per declaration and a prose row per summary, each sized to its text.
    func renderCandidates(_ candidates: [HoverDocument.Candidate], chipBackground: NSColor?) {
        candidatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let innerWidth = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        let chipInnerWidth = innerWidth - 2 * HoverPanelMetrics.chipHorizontalPadding
        // A hairline rule sets the candidates apart from the main declaration's body.
        if !candidates.isEmpty {
            candidatesStack.addArrangedSubview(HoverDocPanel.makeCandidatesSeparator())
        }
        for candidate in candidates where candidate.declaration != nil || candidate.summary != nil {
            if let declaration = candidate.declaration {
                let view = HoverDocPanel.makeCodeTextView(linkDelegate: linkDelegate)
                view.textStorage?.setAttributedString(declaration)
                let chip = HoverDocPanel.makeChip()
                Self.configureChip(chip, around: view)
                chip.fillColor = chipBackground ?? .clear
                let rowHeight =
                    Self.measuredHeight(of: declaration, width: chipInnerWidth)
                    + 2 * HoverPanelMetrics.chipVerticalPadding
                candidatesStack.addArrangedSubview(chip)
                chip.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
                chip.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            }
            if let summary = candidate.summary {
                let view = HoverDocPanel.makeProseTextView(linkDelegate: linkDelegate)
                view.textStorage?.setAttributedString(summary)
                let rowHeight = Self.measuredHeight(of: summary, width: innerWidth)
                candidatesStack.addArrangedSubview(view)
                view.widthAnchor.constraint(equalToConstant: innerWidth).isActive = true
                view.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            }
        }
    }

    func renderDiagnostics(_ diagnostics: [HoverDocument.DiagnosticEntry]) {
        diagnosticsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in diagnostics {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            let bar = NSBox()
            bar.boxType = .custom
            bar.fillColor = entry.severity.tint
            bar.borderWidth = 0
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 3).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 14).isActive = true
            let label = NSTextField(labelWithString: "\(entry.message) — \(entry.tool)")
            label.lineBreakMode = .byWordWrapping
            row.addArrangedSubview(bar)
            row.addArrangedSubview(label)
            diagnosticsStack.addArrangedSubview(row)
        }
    }

    /// The height `text` lays out to at `width`, measured on a throwaway TextKit 2 stack so no slot's view is touched.
    static func measuredHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(text)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return layoutManager.usageBoundsForTextContainer.height
    }

    /// A declaration chip: an `NSBox`, whose fill and border colors resolve at draw time and so follow appearance
    /// changes, unlike a layer's baked `CGColor`s.
    static func makeChip() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = HoverPanelMetrics.chipCornerRadius
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    /// Pins `textView` inside `chip`, inset by the chip padding on every edge.
    static func configureChip(_ chip: NSBox, around textView: NSTextView) {
        chip.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(
                equalTo: chip.leadingAnchor,
                constant: HoverPanelMetrics.chipHorizontalPadding
            ),
            textView.trailingAnchor.constraint(
                equalTo: chip.trailingAnchor,
                constant: -HoverPanelMetrics.chipHorizontalPadding
            ),
            textView.topAnchor.constraint(equalTo: chip.topAnchor, constant: HoverPanelMetrics.chipVerticalPadding),
            textView.bottomAnchor.constraint(
                equalTo: chip.bottomAnchor,
                constant: -HoverPanelMetrics.chipVerticalPadding
            )
        ])
    }

    /// A selectable, read-only text view whose link clicks go through `linkDelegate`.
    static func makeCodeTextView(linkDelegate: HoverLinkDelegate) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.delegate = linkDelegate
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    /// A selectable, read-only text view that wraps to its width, whose link clicks go through `linkDelegate`.
    static func makeProseTextView(linkDelegate: HoverLinkDelegate) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.delegate = linkDelegate
        view.drawsBackground = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainer?.widthTracksTextView = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    /// Quick Help's link to a system symbol's page in Apple's developer documentation, opened as any link of the
    /// panel is, through ``HoverLinkDelegate``.
    static func documentationLink(to url: URL) -> NSAttributedString {
        NSAttributedString(
            string: "Open in Developer Documentation",
            attributes: [.font: NSFont.systemFont(ofSize: HoverTypography.bodySize), .link: url]
        )
    }

    static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
}
