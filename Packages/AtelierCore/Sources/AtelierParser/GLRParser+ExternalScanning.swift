import AtelierGrammar
import Synchronization

/// Scanner-backed parsing keeps lexical state and input position with each GLR branch.
extension GLRParser {
    /// The most on-demand lex modes a parser keeps; past it, it forgets them all and builds them again as needed.
    static let maxViableModes = 64
    /// The most stacks a parse with an external scanner keeps, the preferred ones. Each stack reads the input on its
    /// own, a scanner call and a lex per token, so a stack costs as much as a parse; tree-sitter keeps at most 6
    /// versions, and 10 while it merges. The pinned Swift and JavaScript corpora parse alike with 32 stacks and 256.
    static let maxScanningStacks = 32

    /// Rejects malformed scanner metadata before a parse branch indexes its validity row.
    func validateExternalTable() throws(ParseError) {
        guard parseTable.validExternals.count == parseTable.stateCount,
            parseTable.validExternals.allSatisfy({ $0.count == parseTable.externalNames.count }),
            parseTable.externalSymbols.count == parseTable.externalNames.count,
            parseTable.externalIsExtra.count == parseTable.externalNames.count
        else { throw .parsingFailed("External scanner table is inconsistent") }
    }

    /// `body` over the UTF-8 bytes of `source`, copied only when the string does not store them contiguously.
    static func withUTF8<Value>(of source: String, _ body: (UnsafeBufferPointer<UInt8>) -> Value) -> Value {
        if let value = source.utf8.withContiguousStorageIfAvailable(body) {
            return value
        }
        return Array(source.utf8).withUnsafeBufferPointer(body)
    }

    /// Reads each GLR branch in its own lexical mode and scanner state. Branches can consume different tokens at
    /// the same source position, so they keep their own cursors until they have identical histories again.
    func parseWithExternals(
        _ source: String,
        utf8: UnsafeBufferPointer<UInt8>,
        scanner: TokenScanner,
        externalScanner: any GrammarExternalScanner,
        isCancelled: () -> Bool
    ) throws(ParseError) -> SyntaxTree {
        var active = [ParseStack(state: 0)]
        var finished: [ParseStack] = []
        var scannerValue = externalScanner
        var readCount = 0
        while !active.isEmpty {
            var next: [ParseStack] = []
            while var stack = active.popLast() {
                do throws(ParseError) {
                    if readCount.isMultiple(of: Self.cancellationCheckInterval), isCancelled() {
                        throw ParseError.cancelled(atToken: readCount)
                    }
                    guard readCount < Self.maxTokens * Self.maxScanningStacks else {
                        throw ParseError.tooManyTokens(limit: Self.maxTokens)
                    }
                    let start = stack.cursor
                    guard
                        let token = try nextToken(
                            for: &stack, utf8: utf8, scanner: scanner, externalScanner: &scannerValue)
                    else {
                        finished.append(stack)
                        continue
                    }
                    readCount += 1
                    stack.zeroWidthCount = stack.cursor.offset == start.offset ? stack.zeroWidthCount + 1 : 0
                    guard stack.zeroWidthCount <= max(parseTable.stateCount * 2, 32) else {
                        throw ParseError.parsingFailed("External scanner produced too many zero-width tokens")
                    }
                    // An extra the stack can take as a symbol is one, as tree-sitter reads an extra as such only
                    // where its state has no other action for it: Swift's block comment between class members.
                    if token.isExtra, !(token.terminal.map { canShift($0, on: stack) } ?? false) {
                        stack.extras.append(token)
                        next.append(stack)
                        continue
                    }
                    guard stack.tokenIndex < Self.maxTokens else {
                        throw ParseError.tooManyTokens(limit: Self.maxTokens)
                    }
                    let shifted = try advance([stack], past: token, at: stack.tokenIndex)
                    for var branch in shifted {
                        branch.tokenIndex += 1
                        next.append(branch)
                    }
                } catch {
                    stack.releaseNodes()
                    ParseStack.releaseAll(&active)
                    ParseStack.releaseAll(&next)
                    ParseStack.releaseAll(&finished)
                    throw error
                }
            }
            next = ParseStack.mergingIdenticalHistories(consume next, ranks: symbolRanks)
            next = ParseStack.droppingOutdone(consume next, finished: finished)
            if next.count > Self.maxScanningStacks {
                next.sort { $0.isPreferred(over: $1, ranks: symbolRanks) }
                var dropped = Array(next[Self.maxScanningStacks...])
                next.removeSubrange(Self.maxScanningStacks...)
                ParseStack.releaseAll(&dropped)
            }
            active = next
        }
        guard !finished.isEmpty else { throw .parsingFailed("No valid parse at the end of input") }
        if let end = terminalIndex["$end"] {
            var exceededDepth = false
            finished = applyReduces(to: consume finished, lookahead: end, exceededDepth: &exceededDepth)
            guard !exceededDepth else {
                ParseStack.releaseAll(&finished)
                throw Self.treeTooDeep
            }
        }
        guard let best = ParseStack.takingBest(from: &finished, ranks: symbolRanks) else {
            throw .parsingFailed("No valid parse at the end of input")
        }
        let extras = best.extras
        let end = best.cursor.point
        let errorByteCount = best.errorByteCount
        let root = try buildRootNode(from: consume best, byteCount: utf8.count, endPoint: end)
        return SyntaxTree(
            root: attachingExtras(extras, to: consume root), source: source, errorByteCount: errorByteCount)
    }

    /// `scanned`, which `mode` read, when `stack` can take it or it is an extra; otherwise the token a mode reading only
    /// the tokens of `mode` that `stack` can take reads at the same place, if it reads one.
    ///
    /// A state's mode reads the tokens valid in every context the state stands for, so a token of another context can
    /// win there: in Swift, the text of a string literal, which runs to the next quote, where an identifier ends a
    /// statement. Tree-sitter's lex modes hold no such token, as its states hold no such context.
    private func viableToken(
        _ scanned: TokenScanner.Scanned, readIn mode: Int, by scanner: TokenScanner, for stack: ParseStack,
        utf8: UnsafeBufferPointer<UInt8>, suppressEmptyAt: Int?
    ) -> TokenScanner.Scanned {
        guard !lexTable.tokens[scanned.token].isExtra, let terminal = tokenTerminals[scanned.token],
            !canShift(terminal, on: stack), lexTable.modeValidTokens.indices.contains(mode)
        else { return scanned }
        let tokens = lexTable.modeValidTokens[mode]
        let viable = tokens.filter { token in
            lexTable.tokens[token].isExtra || (tokenTerminals[token].map { canShift($0, on: stack) } ?? false)
        }
        guard viable.count < tokens.count, viable.contains(where: { !lexTable.tokens[$0].isExtra }) else {
            return scanned
        }
        let outcome: TokenScanner.Outcome? = viableModes.withLock { modes in
            // A mode that cannot be built leaves the token as read: the parse takes it as an error.
            guard var viableMode = modes[viable] ?? (try? lexTable.lazyMode(reading: viable)) else { return nil }
            let outcome = scanner.scan(
                utf8, from: stack.cursor, lazyMode: &viableMode, suppressEmptyAt: suppressEmptyAt)
            if modes[viable] == nil, modes.count >= Self.maxViableModes { modes.removeAll() }
            modes[viable] = viableMode
            return outcome
        }
        guard case .token(let relexed)? = outcome else { return scanned }
        return relexed
    }

    /// The token the external scanner reads at `stack`'s cursor with `validSymbols`, which becomes the stack's; nil when
    /// the scanner reads none, or reads one the parse ignores: in error mode, as tree-sitter ignores it, an empty token
    /// that leaves the scanner's state as it was; otherwise an empty one that changes neither that state nor the
    /// parse's.
    private func externalToken(
        for stack: inout ParseStack,
        utf8: UnsafeBufferPointer<UInt8>,
        externalScanner: inout any GrammarExternalScanner,
        validSymbols: [Bool],
        inErrorMode: Bool
    ) throws(ParseError) -> ParseToken? {
        externalScanner.deserialize(stack.scannerState[...])
        var lexer = BufferScannerLexer(utf8, at: stack.cursor)
        guard externalScanner.scan(&lexer, validSymbols: validSymbols) else { return nil }
        guard parseTable.externalNames.indices.contains(lexer.resultSymbol), lexer.tokenEnd.offset <= utf8.count
        else { throw .parsingFailed("External scanner returned an invalid token") }
        var state: [UInt8] = []
        externalScanner.serialize(into: &state)
        guard state.count <= maximumSerializedScannerStateSize else {
            throw .parsingFailed("External scanner state exceeded its size limit")
        }
        let name = parseTable.externalSymbols[lexer.resultSymbol]
        let changesParseState =
            !inErrorMode && (terminalIndex[name].map { parseTable.actions[stack.state][$0] != .error } ?? false)
        guard lexer.tokenEnd.offset > stack.cursor.offset || state != stack.scannerState || changesParseState else {
            return nil
        }
        stack.scannerState = state
        stack.cursor = lexer.tokenEnd
        let start = lexer.tokenStart.offset > lexer.tokenEnd.offset ? lexer.tokenEnd : lexer.tokenStart
        return ParseToken(
            terminal: terminalIndex[name], type: name,
            byteRange: start.offset ..< lexer.tokenEnd.offset,
            pointRange: start.point ..< lexer.tokenEnd.point,
            isNamed: !name.hasPrefix("_") && !name.hasPrefix("\""),
            isExtra: parseTable.externalIsExtra[lexer.resultSymbol])
    }

    /// Reads an external token first when one is valid, then the current state's internal lexical mode.
    private func nextToken(
        for stack: inout ParseStack,
        utf8: UnsafeBufferPointer<UInt8>,
        scanner: TokenScanner,
        externalScanner: inout any GrammarExternalScanner
    ) throws(ParseError) -> ParseToken? {
        let everyExternal = [Bool](repeating: true, count: parseTable.externalNames.count)
        let valid = stack.isRecovering ? everyExternal : viableExternals(for: stack)
        if valid.contains(true),
            let token = try externalToken(
                for: &stack, utf8: utf8, externalScanner: &externalScanner, validSymbols: valid,
                inErrorMode: stack.isRecovering)
        {
            return token
        }

        let mode = scanner.mode(ofState: stack.state) ?? scanner.errorMode
        let suppressEmptyAt = stack.zeroWidthCount > 0 ? stack.cursor.offset : nil
        var outcome =
            mode.map { scanner.scan(utf8, from: stack.cursor, mode: $0, suppressEmptyAt: suppressEmptyAt) }
            ?? .none(start: stack.cursor)
        if case .token(let scanned) = outcome, let mode {
            outcome = .token(
                viableToken(
                    scanned, readIn: mode, by: scanner, for: stack, utf8: utf8, suppressEmptyAt: suppressEmptyAt))
        } else if case .none = outcome {
            // What tree-sitter does when a state's mode reads nothing: it lexes in the error state's mode, whose
            // scanner call has every external valid. Swift's scanner reads `#if` only where a raw string may start,
            // so a directive between two class members is read this way, and the state takes it.
            if !stack.isRecovering, valid != everyExternal, !everyExternal.isEmpty,
                let token = try externalToken(
                    for: &stack, utf8: utf8, externalScanner: &externalScanner, validSymbols: everyExternal,
                    inErrorMode: true)
            {
                return token
            }
            if let errorMode = scanner.errorMode, errorMode != mode {
                outcome = scanner.scan(utf8, from: stack.cursor, mode: errorMode, suppressEmptyAt: suppressEmptyAt)
            }
        }
        switch outcome {
            case .token(let scanned):
                stack.cursor = scanned.end
                return ParseToken(
                    terminal: tokenTerminals[scanned.token], type: lexTable.tokens[scanned.token].name,
                    byteRange: scanned.start.offset ..< scanned.end.offset,
                    pointRange: scanned.start.point ..< scanned.end.point,
                    isNamed: lexTable.tokens[scanned.token].isNamed,
                    isExtra: lexTable.tokens[scanned.token].isExtra)
            case .end(let cursor):
                stack.cursor = cursor
                return nil
            case .none(let start):
                guard start.offset < utf8.count else {
                    stack.cursor = start
                    return nil
                }
                let (scalar, length) = TokenScanner.decode(utf8, at: start.offset)
                var end = start
                end.offset += length
                end.point =
                    scalar == 0x0A
                    ? Point(row: start.point.row + 1, column: 0)
                    : Point(row: start.point.row, column: start.point.column + length)
                stack.cursor = end
                return ParseToken(
                    terminal: nil, type: Unicode.Scalar(scalar).map { String(Character($0)) } ?? "\u{FFFD}",
                    byteRange: start.offset ..< end.offset, pointRange: start.point ..< end.point)
        }
    }
}
