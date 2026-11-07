module Research
  module Agent
    class FixtureModel
      def prepare!
      end

      def call(input:, tools:, output_tokens:, timeout:, request_key:, check:, forbidden: [], &delta)
        check.call
        results = input.select { |item| item["type"] == "function_call_output" }
        name = results.empty? ? "GetEarningsCallEvent" : (results.size == 1 ? "GetEarningsBrief" : nil)
        arguments = { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 }
        arguments["limit"] = 1 if name == "GetEarningsBrief"
        calls = name ? [ToolCall.new(id: "fixture_#{results.size}", name: name, arguments: arguments)] : []
        output = calls.map { |call| { "type" => "function_call", "call_id" => call.id, "name" => call.name,
                                     "arguments" => JSON.generate(call.arguments) } }
        source = results.last && JSON.parse(results.last["output"])
        text = name ? "" : "Original fictional Alpha reported 120 demonstration units of revenue [#{source.fetch('source_id')}]. Not real financial data or investment advice."
        delta&.call(text) if text.present?
        ModelResult.new(text: text, tool_calls: calls, output: output, deltas: text.present? ? [text] : [],
          usage: Usage.new(input_tokens: Chunker.new.tokens(JSON.generate(input)), output_tokens: [Chunker.new.tokens(text), 32].max))
      end
    end
  end
end
