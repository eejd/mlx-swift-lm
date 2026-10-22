// Copyright © 2026 Apple Inc.

import Foundation
import Testing

@testable import MLXLMCommon

/// A request that offers no tools has nothing a tool call could name. A JSON answer
/// with a `name` key is shaped like a Llama 3 call (`{"name": ..., "parameters": ...}`)
/// and must stay response text then; only a marked attempt is a (rejected) call.
@Suite("Tool calls without declared tools")
struct UnmarkedJSONToolCallTests {
    private static let weather: [[String: any Sendable]] = [
        [
            "type": "function",
            "function": [
                "name": "get_weather",
                "parameters": [
                    "type": "object",
                    "properties": ["city": ["type": "string"] as [String: any Sendable]]
                        as [String: any Sendable],
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ]
    ]

    private static let person = #"{"name": "Jane Doe", "age": 31, "email": "jane@example.com"}"#
    private static let personWithParameters = #"{"name": "Jane Doe", "parameters": {"age": 31}}"#
    private static let personWithArguments = #"{"name": "Jane Doe", "arguments": {"age": 31}}"#

    private func run(
        _ text: String, format: ToolCallFormat, tools: [[String: any Sendable]]?, size: Int
    ) -> (response: String, calls: [ToolCall], rejected: [RejectedToolCall]) {
        let processor = ToolCallProcessor(format: format, tools: tools)
        var response = ""
        var rest = Substring(text)
        while !rest.isEmpty {
            response += processor.processChunk(String(rest.prefix(size))) ?? ""
            rest = rest.dropFirst(size)
        }
        response += processor.processEOS(returnBufferedText: true) ?? ""
        return (response, processor.toolCalls, processor.rejectedToolCalls)
    }

    @Test(
        "A JSON answer is response text when no tool is offered",
        arguments: [ToolCallFormat.llama3, .json], [1, 5, Int.max])
    func jsonAnswerIsResponse(format: ToolCallFormat, size: Int) {
        for answer in [Self.person, Self.personWithParameters, Self.personWithArguments] {
            let result = run(answer, format: format, tools: [], size: size)
            #expect(result.response == answer)
            #expect(result.calls.isEmpty)
            #expect(result.rejected.isEmpty)
        }
    }

    @Test("Text before a JSON answer is kept with it")
    func answerAfterText() {
        let text = "Here it is: " + Self.person
        let result = run(text, format: .llama3, tools: [], size: 4)
        #expect(result.response == text)
        #expect(result.calls.isEmpty)
        #expect(result.rejected.isEmpty)
    }

    @Test("A JSON answer cut off by the end of the stream is response text")
    func truncatedAnswer() {
        let answer = #"{"name": "Jane Doe", "parameters": {"age": 3"#
        for format in [ToolCallFormat.llama3, .json] {
            let result = run(answer, format: format, tools: [], size: 4)
            #expect(result.response == answer)
            #expect(result.rejected.isEmpty)
        }
    }

    @Test("A marked attempt is still a rejected call when no tool is offered")
    func markedAttemptIsRejected() {
        // The tag arrives whole, as the tokenizer emits it (it is one special token).
        let python = run("<|python_tag|>" + Self.person, format: .llama3, tools: [], size: .max)
        #expect(python.calls.isEmpty)
        #expect(python.rejected.map(\.reason) == [.undeclaredTool])

        let framed = run(
            "<tool_call>" + Self.personWithArguments + "</tool_call>", format: .json, tools: [],
            size: 6)
        #expect(framed.calls.isEmpty)
        #expect(framed.rejected.map(\.reason) == [.undeclaredTool])
    }

    @Test(
        "A declared tool is still called",
        arguments: [ToolCallFormat.llama3, .json], [1, 5, Int.max])
    func declaredToolIsCalled(format: ToolCallFormat, size: Int) {
        let call = #"{"name": "get_weather", "arguments": {"city": "Paris"}}"#
        let result = run(call, format: format, tools: Self.weather, size: size)
        #expect(result.response.isEmpty)
        #expect(result.rejected.isEmpty)
        #expect(result.calls.count == 1)
        #expect(result.calls.first?.function.name == "get_weather")
        #expect(result.calls.first?.function.arguments == ["city": .string("Paris")])
    }

    @Test("Without a declared list every tool-shaped object is a call, as before")
    func noListAcceptsAnyName() {
        let result = run(Self.person, format: .llama3, tools: nil, size: 5)
        #expect(result.calls.map(\.function.name) == ["Jane Doe"])
        #expect(result.response.isEmpty)
    }

    @Test("An undeclared name is rejected when other tools are offered")
    func undeclaredNameWithTools() {
        let result = run(Self.personWithArguments, format: .json, tools: Self.weather, size: 5)
        #expect(result.calls.isEmpty)
        #expect(result.rejected.map(\.reason) == [.undeclaredTool])
    }
}
