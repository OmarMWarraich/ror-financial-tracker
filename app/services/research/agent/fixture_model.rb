module Research
  module Agent
    class FixtureModel
      def prepare!
      end

      def call(input:, tools:, output_tokens:, timeout:, request_key:, check:, forbidden: [], &delta)
        check.call
        workflow = input.any? { |item| item["role"] == "developer" && item["content"] == EarningsWorkflow::PROMPT }
        results = input.select { |item| item["type"] == "function_call_output" }
        name = results.empty? ? "GetEarningsCallEvent" : (results.size == 1 ? (workflow ? "GetEarningsCallTranscript" : "GetEarningsBrief") : nil)
        arguments = { "ticker" => "ALPHA", "fiscalYear" => 2026, "fiscalQuarter" => 3 }
        arguments["limit"] = 1 if name == "GetEarningsBrief"
        arguments.merge!("limit" => 50, "offset" => 0) if name == "GetEarningsCallTranscript"
        calls = name ? [ToolCall.new(id: "fixture_#{results.size}", name: name, arguments: arguments)] : []
        output = calls.map { |call| { "type" => "function_call", "call_id" => call.id, "name" => call.name,
                                     "arguments" => JSON.generate(call.arguments) } }
        source = results.last && JSON.parse(results.last["output"])
        text = name ? "" : "Original fictional Alpha reported 120 demonstration units of revenue [#{source.fetch('source_id')}]. Not real financial data or investment advice."
        if workflow && name.nil?
          claim = { "kind" => "reported", "source_id" => source.fetch("source_id"),
            "quote" => "Fictional Chief Executive: revenue was 120 demonstration units." }
          text = JSON.generate("workflow" => EarningsWorkflow::ID, "listing_identity" => "SYNTH:ALPHA",
            "fiscal_year" => 2026, "fiscal_quarter" => 3, "status" => "answer",
            "sections" => { "summary" => [claim], "results" => [claim], "outlook" => [], "risks" => [] }, "gaps" => [])
        end
        delta&.call(text) if text.present?
        ModelResult.new(text: text, tool_calls: calls, output: output, deltas: text.present? ? [text] : [],
          usage: Usage.new(input_tokens: Chunker.new.tokens(JSON.generate(input)), output_tokens: [Chunker.new.tokens(text), 32].max))
      end
    end
  end
end
