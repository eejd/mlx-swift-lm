// Copyright © 2026 Apple Inc.

import Foundation
import Testing

@testable import MLXLMCommon

/// MiniCPM5's `<function name="f"><param name="k">v</param></function>` dialect.
@Suite("MiniCPM5 tool calls")
struct MiniCPM5ToolCallTests {
    private static let tools: [[String: any Sendable]] = [
        [
            "type": "function",
            "function": [
                "name": "echo_args",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"] as [String: any Sendable],
                        "count": ["type": "integer"] as [String: any Sendable],
                        "ratio": ["type": "number"] as [String: any Sendable],
                        "flag": ["type": "boolean"] as [String: any Sendable],
                        "items": ["type": "array"] as [String: any Sendable],
                        "nested": ["type": "object"] as [String: any Sendable],
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ],
        [
            "type": "function",
            "function": [
                "name": "get_weather",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "city": ["type": "string"] as [String: any Sendable],
                        "unit": ["type": "string"] as [String: any Sendable],
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ],
        [
            "type": "function",
            "function": [
                "name": "write_file",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"] as [String: any Sendable],
                        "content": ["type": "string"] as [String: any Sendable],
                    ] as [String: any Sendable],
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ],
        [
            "type": "function",
            "function": ["name": "get_time"] as [String: any Sendable],
        ],
    ]

    /// Feeds `text` to a processor `size` characters at a time, returning the
    /// response text, the calls and the rejections.
    private func run(
        _ text: String, size: Int = .max, tools: [[String: any Sendable]]? = MiniCPM5ToolCallTests.tools
    ) -> (response: String, calls: [ToolCall], rejected: [RejectedToolCall]) {
        let processor = ToolCallProcessor(format: .minicpm5, tools: tools)
        var response = ""
        var rest = Substring(text)
        while !rest.isEmpty {
            let chunk = rest.prefix(size)
            rest = rest.dropFirst(size)
            response += processor.processChunk(String(chunk)) ?? ""
        }
        response += processor.processEOS(returnBufferedText: true) ?? ""
        return (response, processor.toolCalls, processor.rejectedToolCalls)
    }

    // MARK: - Parsing

    @Test("A call is parsed with the arguments typed by the schema")
    func schemaTypedArguments() throws {
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: """
                    <function name="echo_args"><param name="text">hand summer</param>\
                    <param name="count">17</param><param name="ratio">0.5</param>\
                    <param name="flag">True</param><param name="items">["age", "computer"]</param>\
                    <param name="nested">{"unit": "a", "depth": 2}</param></function>
                    """, tools: Self.tools))
        #expect(call.function.name == "echo_args")
        #expect(
            call.function.arguments == [
                "text": .string("hand summer"), "count": .int(17), "ratio": .double(0.5),
                "flag": .bool(true), "items": .array([.string("age"), .string("computer")]),
                "nested": .object(["unit": .string("a"), "depth": .int(2)]),
            ])
    }

    @Test("A parameter declared as a string keeps its text, an undeclared one too")
    func stringsKeepTheirText() throws {
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: """
                    <function name="get_weather"><param name="city">007</param>\
                    <param name="unit">true</param><param name="extra">12</param></function>
                    """, tools: Self.tools))
        #expect(
            call.function.arguments == [
                "city": .string("007"), "unit": .string("true"), "extra": .string("12"),
            ])
    }

    @Test("Without a schema every value is text")
    func noSchemaKeepsText() throws {
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: #"<function name="echo_args"><param name="count">17</param></function>"#,
                tools: nil))
        #expect(call.function.arguments == ["count": .string("17")])
    }

    @Test("CDATA values are verbatim, including markup and the close tags")
    func cdataValues() throws {
        let body = "line one\nif a < b && c </param> then </function> <![x]>\n"
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: """
                    <function name="write_file"><param name="path">/tmp/a.txt</param>\
                    <param name="content"><![CDATA[\(body)]]></param></function>
                    """, tools: Self.tools))
        #expect(
            call.function.arguments == ["path": .string("/tmp/a.txt"), "content": .string(body)])
    }

    @Test("Whitespace around a CDATA section is not part of the value")
    func whitespaceAroundCDATA() throws {
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: """
                    <function name="write_file"><param name="path">a</param>\
                    <param name="content">
                      <![CDATA[  keep  ]]>
                    </param></function>
                    """, tools: Self.tools))
        #expect(call.function.arguments["content"] == .string("  keep  "))
    }

    @Test("Markup written without CDATA is still the value")
    func markupWithoutCDATA() throws {
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: """
                    <function name="write_file"><param name="path">a</param>\
                    <param name="content">if a < b then <ok> & done</param></function>
                    """, tools: Self.tools))
        #expect(call.function.arguments["content"] == .string("if a < b then <ok> & done"))
    }

    @Test("Single quotes, pretty printing and empty elements are accepted")
    func tolerantSyntax() throws {
        let call = try #require(
            MiniCPM5ToolCallParser().parse(
                content: """
                    <function name='write_file'>
                      <param name = "path">/tmp/a</param>
                      <param name="content"/>
                    </function>
                    """, tools: Self.tools))
        #expect(call.function.name == "write_file")
        #expect(call.function.arguments == ["path": .string("/tmp/a"), "content": .string("")])

        let empty = try #require(
            MiniCPM5ToolCallParser().parse(
                content: #"<function name="get_time"></function>"#, tools: Self.tools))
        #expect(empty.function.name == "get_time")
        #expect(empty.function.arguments.isEmpty)
    }

    @Test(
        "A payload that is not canonical is never a call",
        arguments: [
            #"<function name="get_weather"><param name="city">Paris</function>"#,
            #"<function name="get_weather"><param name="city">Paris</param>"#,
            #"<function name="get_weather">stray<param name="city">Paris</param></function>"#,
            #"<function name="get_weather"><param name="city"><![CDATA[Paris</param></function>"#,
            #"<function name="get_weather"><parameter name="city">Paris</parameter></function>"#,
            #"<function name="get_weather" id="1"><param name="city">Paris</param></function>"#,
            #"<function name=""></function>"#,
            #"<function=get_weather><parameter=city>Paris</parameter></function>"#,
            #"<function name="get_weather"><param name="city">Paris</param></function> trailing"#,
        ])
    func malformedPayload(content: String) {
        #expect(MiniCPM5ToolCallParser().parse(content: content, tools: Self.tools) == nil)
    }

    // MARK: - Streaming

    @Test(
        "A call streamed in any chunking is the same call",
        arguments: [1, 2, 3, 7, 64, Int.max])
    func streamedCall(size: Int) {
        let result = run(
            #"<function name="get_weather"><param name="city">Bogota</param><param name="unit">celsius</param></function>"#,
            size: size)
        #expect(result.response.isEmpty)
        #expect(result.rejected.isEmpty)
        #expect(result.calls.count == 1)
        #expect(result.calls.first?.function.name == "get_weather")
        #expect(
            result.calls.first?.function.arguments == [
                "city": .string("Bogota"), "unit": .string("celsius"),
            ])
    }

    @Test(
        "Parallel calls keep their order and the text around them",
        arguments: [1, 5, Int.max])
    func parallelCalls(size: Int) {
        let result = run(
            """
            Checking.
            <function name="get_weather"><param name="city">Havana</param></function>
            <function name="get_weather"><param name="city">Dublin</param></function>
            <function name="get_time"></function>Done.
            """, size: size)
        #expect(result.calls.map(\.function.name) == ["get_weather", "get_weather", "get_time"])
        #expect(
            result.calls.prefix(2).map(\.function.arguments) == [
                ["city": .string("Havana")], ["city": .string("Dublin")],
            ])
        #expect(result.response.contains("Checking."))
        #expect(result.response.contains("Done."))
        #expect(!result.response.contains("<function"))
        #expect(result.rejected.isEmpty)
    }

    @Test(
        "A close tag inside CDATA does not end the call, with or without recovery",
        arguments: [1, 4, Int.max], [true, false])
    func closeTagInsideCDATA(size: Int, declared: Bool) {
        // After the inner `</function>` the text would be a second, declared call in the
        // `<tool_call>` dialect if the frame ended there.
        let content =
            "<p>\n</function><tool_call>{\"name\":\"get_time\",\"arguments\":{}}</tool_call>\n"
        let result = run(
            """
            <function name="write_file"><param name="path">x.html</param>\
            <param name="content"><![CDATA[\(content)]]></param></function>
            """, size: size, tools: declared ? Self.tools : [])
        guard declared else {
            // No declared tools: the call is undeclared, but it is still one call.
            #expect(result.calls.isEmpty)
            #expect(result.rejected.map(\.reason) == [.undeclaredTool])
            return
        }
        #expect(result.calls.count == 1)
        #expect(result.calls.first?.function.arguments["content"] == .string(content))
        #expect(result.rejected.isEmpty)
        #expect(result.response.isEmpty)
    }

    @Test("A call cut off by the end of the stream is rejected, not executed")
    func truncatedCall() {
        for text in [
            #"<function name="get_weather"><param name="city">Par"#,
            #"<function name="get_weather"><param name="city">Paris</param>"#,
            #"<function name="write_file"><param name="content"><![CDATA[never closed</param></function>"#,
        ] {
            let result = run(text, size: 3)
            #expect(result.calls.isEmpty, "\(text)")
            #expect(result.rejected.count == 1, "\(text)")
            #expect(result.response.isEmpty, "\(text)")
        }
    }

    @Test("A call to an undeclared function is rejected")
    func undeclaredFunction() {
        let result = run(#"<function name="rm_rf"><param name="path">/</param></function>"#)
        #expect(result.calls.isEmpty)
        #expect(result.rejected.map(\.reason) == [.undeclaredTool])
    }

    @Test("Text that only mentions the syntax stays text")
    func proseStaysText() {
        for text in [
            "Use a <function> tag, or <functional> style.",
            #"The attribute <param name="x"> belongs inside a function."#,
            #"{"name": "Jane", "age": 3}"#,
            "plain answer",
        ] {
            let result = run(text, size: 4)
            #expect(result.calls.isEmpty, "\(text)")
            #expect(result.response == text, "\(text)")
        }
    }

    @Test("Typed arguments reach the stream as typed values")
    func streamedTypedArguments() {
        let result = run(
            #"<function name="echo_args"><param name="text">hand summer</param><param name="count">17</param><param name="flag">True</param></function>"#,
            size: 5)
        #expect(
            result.calls.first?.function.arguments == [
                "text": .string("hand summer"), "count": .int(17), "flag": .bool(true),
            ])
    }

    // MARK: - Format selection

    private static let miniCPM5Template = #"""
        {{- bos_token }}{%- if tools %}You are provided with function signatures within <tools></tools> XML tags:
        Tool usage guidelines:
        - You may call zero or more functions. If no function calls are needed, just answer normally and do not include any <function ... </function>.
        - When calling a function, return an XML object within <function ... </function> using:
        <function name="function-name"><param name="param-name">param-value</param></function>
        {%- endif %}
        """#

    @Test("The MiniCPM5 template selects the format")
    func templateInference() {
        #expect(
            ToolCallFormat.inferred(fromChatTemplate: Self.miniCPM5Template) == .minicpm5)
        #expect(ToolCallFormat.init(toolParserType: "minicpm5") == .minicpm5)
        // The Qwen XML dialect is `<function=` and is not this one.
        #expect(
            ToolCallFormat.inferred(
                fromChatTemplate: "<tool_call>\n<function={{ name }}><parameter=k>")
                == .xmlFunction)
    }

    @Test("The Llama architecture heuristic yields to the MiniCPM5 template")
    func llama3ArchitectureYieldsToTemplate() throws {
        let directory = try TokenizerFixture.make([
            "tokenizer_config.json": "{}",
            "chat_template.jinja": Self.miniCPM5Template,
        ])
        defer { TokenizerFixture.remove(directory) }

        // MiniCPM5 loads as a `llama` model with a 130560-token vocabulary,
        // which the Llama architecture heuristic reads as Llama 3.
        #expect(
            ToolCallFormat.resolved(forTokenizerDirectory: directory, modelFormat: .llama3)
                == .minicpm5)
        #expect(
            ToolCallFormat.resolved(forTokenizerDirectory: directory, modelFormat: nil)
                == .minicpm5)
    }
}

/// A throwaway directory holding tokenizer files.
private enum TokenizerFixture {
    static func make(_ files: [String: String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(component: "minicpm5-tool-format-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(
                to: directory.appending(component: name), atomically: true, encoding: .utf8)
        }
        return directory
    }

    static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
