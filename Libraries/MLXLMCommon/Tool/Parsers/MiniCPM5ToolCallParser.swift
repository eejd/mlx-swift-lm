// Copyright © 2026 Apple Inc.

import Foundation

/// Parser for MiniCPM5's function format.
///
/// The chat template teaches the model
/// `<function name="f"><param name="k">v</param></function>` with no outer
/// wrapper. Parallel calls are consecutive `<function>` blocks, and a value that
/// contains `<`, `&` or a newline is written as `<![CDATA[...]]>`.
/// Reference: https://huggingface.co/openbmb/MiniCPM5-2B/blob/main/chat_template.jinja
///
/// The call is scanned, not run through an XML parser, because the model does
/// not always wrap markup in CDATA (`<param name="text">if a < b then <ok> &
/// done</param>`): a value is the text up to its `</param>`, or the CDATA
/// section when there is one, so markup characters inside it never invalidate
/// the call. The structural scan (shared with the streaming framer through
/// ``MiniCPM5ToolCallParser/frameEnd(in:)``) skips over CDATA, so a payload that
/// contains `</param>` or `</function>` is a value, not a close.
///
/// A value is read through the argument schema like every other dialect:
/// a parameter declared `string` keeps its text verbatim, a declared integer,
/// number, boolean, array or object is typed, and an undeclared parameter keeps
/// its text. A payload that is not canonical in full (an unclosed parameter,
/// text between parameters, an unterminated CDATA section) is never turned into
/// a call with silently missing arguments.
public struct MiniCPM5ToolCallParser: ToolCallParser, Sendable {
    public let startTag: String? = MiniCPM5PayloadScanner.functionOpenTag
    public let endTag: String? = MiniCPM5PayloadScanner.functionClose

    public init() {}

    public func parse(content: String, tools: [[String: any Sendable]]?) -> ToolCall? {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)[...]
        guard case .complete(let payload) = MiniCPM5PayloadScanner.scan(text),
            text[payload.end...].allSatisfy(\.isWhitespace)
        else { return nil }
        return payload.toolCall(tools: tools)
    }

    /// Every consecutive call in `toolCallBuffer`. A buffer that ends inside a
    /// call yields the calls before it and never the unfinished one.
    public func parseEOS(_ toolCallBuffer: String, tools: [[String: any Sendable]]?) -> [ToolCall] {
        var calls: [ToolCall] = []
        var remainder = toolCallBuffer[...]
        while true {
            remainder = remainder.drop(while: \.isWhitespace)
            guard !remainder.isEmpty,
                case .complete(let payload) = MiniCPM5PayloadScanner.scan(remainder)
            else { return calls }
            calls.append(payload.toolCall(tools: tools))
            remainder = remainder[payload.end...]
        }
    }

    /// The structural close of the call at the start of `buffer`: `</function>`
    /// is a close only outside every CDATA section and parameter value.
    /// A call that is still open waits for more text; a buffer that violates
    /// the structure falls back to the first textual `</function>`, so the
    /// parser can decline the complete payload and report it as rejected.
    public func frameEnd(in buffer: String) -> String.Index? {
        switch MiniCPM5PayloadScanner.scan(buffer[...]) {
        case .complete(let payload): return payload.end
        case .needMore: return nil
        case .malformed:
            return buffer.range(of: MiniCPM5PayloadScanner.functionClose)?.upperBound
        }
    }
}

/// Structural scanner for `<function name="f"><param name="k">v</param>...</function>`.
enum MiniCPM5PayloadScanner {

    /// A structurally complete call.
    struct Payload {
        let name: String
        /// Parameters in source order, each value already resolved (CDATA
        /// unwrapped).
        let parameters: [(name: String, value: String)]
        /// Index just past `</function>` (or past `/>` for an empty call).
        let end: String.Index
    }

    enum ScanResult {
        /// The call is structurally complete.
        case complete(Payload)
        /// The buffer ended before completeness or malformation could be
        /// decided; more input may still complete it.
        case needMore
        /// A structural violation was found.
        case malformed
    }

    static let functionOpenTag = "<function name="
    static let functionClose = "</function>"
    private static let functionOpen = "<function"
    private static let paramOpen = "<param"
    private static let paramClose = "</param>"
    private static let cdataOpen = "<![CDATA["
    private static let cdataClose = "]]>"

    /// Scan one call that must begin at the start of `text`.
    static func scan(_ text: Substring) -> ScanResult {
        var index = text.startIndex
        let function: OpenTag
        switch openTag(functionOpen, in: text, at: index) {
        case .tag(let tag): function = tag
        case .needMore: return .needMore
        case .malformed: return .malformed
        }
        index = function.end
        // `<function name="f"/>` is not the template's spelling (`<function name="f"></function>`
        // is) and carries no `</function>` for the streaming framer to wait for.
        guard !function.name.isEmpty, !function.isSelfClosing else { return .malformed }

        var parameters: [(name: String, value: String)] = []
        while true {
            index = skipWhitespace(in: text, from: index)
            guard index < text.endIndex else { return .needMore }

            switch matchLiteral(functionClose, in: text, at: index) {
            case .matched(let after):
                return .complete(
                    Payload(name: function.name, parameters: parameters, end: after))
            case .needMore:
                return .needMore
            case .noMatch:
                break
            }

            let parameter: OpenTag
            switch openTag(paramOpen, in: text, at: index) {
            case .tag(let tag): parameter = tag
            case .needMore: return .needMore
            case .malformed: return .malformed
            }
            guard !parameter.name.isEmpty else { return .malformed }
            if parameter.isSelfClosing {
                parameters.append((name: parameter.name, value: ""))
                index = parameter.end
                continue
            }
            switch value(in: text, from: parameter.end) {
            case .value(let value, let after):
                parameters.append((name: parameter.name, value: value))
                index = after
            case .needMore:
                return .needMore
            }
        }
    }

    // MARK: - Tags

    private struct OpenTag {
        let name: String
        let isSelfClosing: Bool
        let end: String.Index
    }

    private enum OpenTagResult {
        case tag(OpenTag)
        case needMore
        case malformed
    }

    /// `<tag name="value">` or `<tag name='value'/>`; the `name` attribute is
    /// the only one the dialect has.
    private static func openTag(
        _ tag: String, in text: Substring, at start: String.Index
    ) -> OpenTagResult {
        var index = start
        switch matchLiteral(tag, in: text, at: index) {
        case .matched(let after): index = after
        case .needMore: return .needMore
        case .noMatch: return .malformed
        }
        // The whitespace separates the tag name from its attribute
        // (`<functional>` and `<parameter>` are other tags).
        guard index < text.endIndex else { return .needMore }
        guard text[index].isWhitespace else { return .malformed }
        index = skipWhitespace(in: text, from: index)

        switch matchLiteral("name", in: text, at: index) {
        case .matched(let after): index = after
        case .needMore: return .needMore
        case .noMatch: return .malformed
        }
        index = skipWhitespace(in: text, from: index)
        guard index < text.endIndex else { return .needMore }
        guard text[index] == "=" else { return .malformed }
        index = skipWhitespace(in: text, from: text.index(after: index))
        guard index < text.endIndex else { return .needMore }
        let quote = text[index]
        guard quote == "\"" || quote == "'" else { return .malformed }
        let nameStart = text.index(after: index)
        guard let nameEnd = text[nameStart...].firstIndex(of: quote) else { return .needMore }
        let name = String(text[nameStart ..< nameEnd])
        guard !name.contains(where: { $0 == "<" || $0 == ">" }) else { return .malformed }
        index = skipWhitespace(in: text, from: text.index(after: nameEnd))
        guard index < text.endIndex else { return .needMore }

        var isSelfClosing = false
        if text[index] == "/" {
            isSelfClosing = true
            index = text.index(after: index)
            guard index < text.endIndex else { return .needMore }
        }
        guard text[index] == ">" else { return .malformed }
        return .tag(
            OpenTag(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                isSelfClosing: isSelfClosing, end: text.index(after: index)))
    }

    // MARK: - Values

    private enum ValueResult {
        case value(String, after: String.Index)
        case needMore
    }

    /// Reads a parameter value up to its `</param>`, skipping every CDATA
    /// section on the way, and resolves it.
    private static func value(in text: Substring, from start: String.Index) -> ValueResult {
        var parts: [(text: Substring, isCDATA: Bool)] = []
        var index = start
        while true {
            let close = text.range(of: paramClose, range: index ..< text.endIndex)
            let cdata = text.range(of: cdataOpen, range: index ..< text.endIndex)
            if let cdata, close == nil || cdata.lowerBound < close!.lowerBound {
                guard
                    let cdataEnd = text.range(
                        of: cdataClose, range: cdata.upperBound ..< text.endIndex)
                else { return .needMore }
                parts.append((text[index ..< cdata.lowerBound], false))
                parts.append((text[cdata.upperBound ..< cdataEnd.lowerBound], true))
                index = cdataEnd.upperBound
                continue
            }
            guard let close else { return .needMore }
            parts.append((text[index ..< close.lowerBound], false))
            return .value(resolved(parts), after: close.upperBound)
        }
    }

    /// A value that is one CDATA section (only whitespace around it) is the
    /// section's payload, verbatim. Anything else is its text as written, with
    /// any CDATA section inside it unwrapped.
    private static func resolved(_ parts: [(text: Substring, isCDATA: Bool)]) -> String {
        let sections = parts.filter(\.isCDATA)
        if sections.count == 1,
            parts.allSatisfy({ $0.isCDATA || $0.text.allSatisfy(\.isWhitespace) })
        {
            return String(sections[0].text)
        }
        return parts.reduce(into: "") { $0 += $1.text }
    }

    // MARK: - Characters

    private static func skipWhitespace(in text: Substring, from index: String.Index)
        -> String.Index
    {
        var index = index
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        return index
    }

    private enum LiteralMatch {
        case matched(after: String.Index)
        case needMore
        case noMatch
    }

    /// Match `literal` at `index`, distinguishing "not here" from "the buffer
    /// ended while it could still complete".
    private static func matchLiteral(
        _ literal: String, in text: Substring, at index: String.Index
    ) -> LiteralMatch {
        var literalIndex = literal.startIndex
        var textIndex = index
        while literalIndex < literal.endIndex {
            guard textIndex < text.endIndex else { return .needMore }
            guard text[textIndex] == literal[literalIndex] else { return .noMatch }
            literalIndex = literal.index(after: literalIndex)
            textIndex = text.index(after: textIndex)
        }
        return .matched(after: textIndex)
    }
}

extension MiniCPM5PayloadScanner.Payload {

    /// How a canonical call becomes arguments: every value is read through the
    /// argument schema (`convertParameterValue`), so a declared `string` keeps
    /// its text and an undeclared parameter keeps its text as well.
    func toolCall(tools: [[String: any Sendable]]?) -> ToolCall {
        var arguments: [String: any Sendable] = [:]
        for parameter in parameters {
            arguments[parameter.name] = convertParameterValue(
                parameter.value, paramName: parameter.name, funcName: name, tools: tools)
        }
        return ToolCall(function: .init(name: name, arguments: arguments))
    }
}
