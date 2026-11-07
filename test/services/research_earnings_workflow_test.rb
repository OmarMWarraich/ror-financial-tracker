require "test_helper"

class ResearchEarningsWorkflowTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  Agent = Research::Agent

  setup do
    @user = User.create!(email: "original-workflow-#{SecureRandom.uuid}@example.test", password: "original-fixture-password")
    @scope = { "listing_identity" => "SYNTH:ALPHA", "fiscal_year" => 2026, "fiscal_quarter" => 3 }
    @source = @scope.merge("source_id" => "original:transcript", "tool" => "GetEarningsCallTranscript",
      "content" => "Fictional CEO: revenue was 120 demonstration units. We expect 130 demonstration units.",
      "synthetic" => true, "provider_event_id" => Agent::FixtureTools::EVENT_ID, "coverage" => { "complete_call" => false })
    @claim = { "kind" => "reported", "source_id" => @source["source_id"],
      "quote" => "Fictional CEO: revenue was 120 demonstration units." }
    @answer = @scope.merge("workflow" => Agent::EarningsWorkflow::ID, "status" => "answer",
      "sections" => { "summary" => [@claim], "results" => [@claim], "outlook" => [], "risks" => [] }, "gaps" => [])
  end

  teardown do
    @user.with_lock do
      [ResearchToolAttempt, ResearchMessage, ResearchModelAttempt, ResearchAgentRun, ResearchConversation].each { |model| model.where(user: @user).delete_all }
    end
    @user.destroy!
  end

  test "versioned original workflow and scoped followups have zero external cost and fresh evidence each turn" do
    first = submit
    Agent::Execution.call(first)
    assert_equal Agent::EarningsWorkflow::ID, first.workflow_version
    assert_equal Agent::EarningsWorkflow::PROMPT_VERSION, first.prompt_version
    second = submit(conversation: first.conversation, query: "What does the selected scope establish?")
    result = Agent::Execution.call(second)
    assert_equal "completed", result.status
    %w[Summary Results Outlook Risks].each { |section| assert_includes result.text, "## #{section}" }
    assert_includes result.text, "Model synthesis: extractive selection"
    assert_includes result.text, "missing guidance"
    assert_equal 2, second.tool_attempts.count
    assert_equal 0, Agent::Spend.conversation(first.conversation)
    assert_equal "workflow_scope_conflict", assert_raises(Research::Error) { submit(conversation: first.conversation, query: "Summarize US:MSFT FY2025 Q4") }.code
    assert_equal 2, first.conversation.runs.count
  end

  test "unsupported numbers citations classifications scope and malformed output never publish" do
    assert_equal "workflow_claim_unsupported", failure { @claim["quote"] = "Revenue was 999 demonstration units."; answer }.code
    @claim["quote"] = @source["content"].split(" We").first
    @claim["source_id"] = "not-supplied"
    assert_equal "workflow_claim_unsupported", failure { answer }.code
    @claim["source_id"] = @source["source_id"]
    @claim["kind"] = "provider_interpretation"
    assert_equal "workflow_claim_misclassified", failure { answer }.code
    @claim["kind"] = "reported"
    @source["listing_identity"] = "US:MSFT"
    assert_equal "workflow_evidence_scope_mismatch", failure { answer }.code
    assert_equal "workflow_answer_invalid", failure { Agent::EarningsWorkflow.answer("not JSON", sources: [], scope: @scope, event: Agent::EarningsWorkflow.fixture_event) }.code
    assert_equal "workflow_event_scope_mismatch", failure { Agent::EarningsWorkflow.answer(JSON.generate(@answer),
      sources: [], scope: @scope, event: Agent::EarningsWorkflow.fixture_event.merge("fiscal_quarter" => 2)) }.code
  end

  test "guidance provider interpretation uncertainty and abstention are explicit rather than fabricated results" do
    @claim.merge!("kind" => "guidance", "quote" => @source["content"])
    assert_includes answer[:text], "Management guidance (not a reported result)"
    @claim["kind"] = "reported"
    assert_equal "workflow_claim_misclassified", failure { answer }.code
    @source["tool"] = "GetEarningsBrief"
    @claim["kind"] = "provider_interpretation"
    assert_includes answer[:text], "Provider-generated interpretation"
    @answer["status"] = "abstain"
    @answer["sections"] = Agent::EarningsWorkflow::SECTIONS.index_with { [] }
    @answer["gaps"] = ["conflicting_evidence"]
    result = answer
    assert_equal "no_evidence", result[:status]
    assert_includes result[:text], "Abstained"
    assert_not_includes result[:text], "revenue was 120"
  end

  test "whole runtime settles known usage but cannot publish rejected financial claims or fabricated abstention" do
    %w[unsupported abstain].each do |mode|
      model = Class.new(Agent::FixtureModel) do
        define_method(:call) do |**options, &block|
          result = super(**options, &block)
          if result.tool_calls.empty?
            value = JSON.parse(result.text)
            if mode == "unsupported"
              value["sections"]["summary"].first["quote"] = "Revenue was 999 demonstration units."
            else
              value["status"] = "abstain"
              value["sections"] = Agent::EarningsWorkflow::SECTIONS.index_with { [] }
              value["gaps"] = ["insufficient_material"]
            end
            result.text = JSON.generate(value)
            result.deltas = [result.text]
          end
          result
        end
      end.new
      run = submit
      events = []
      if mode == "unsupported"
        assert_equal "workflow_claim_unsupported", failure { Agent::Execution.call(run, model: model, events: ->(event) { events << event }) }.code
        assert_equal "failed", run.reload.state
        assert_nil run.messages.find_by!(role: "assistant").content
        assert_not events.any? { |event| event["type"] == "text.delta" }
      else
        result = Agent::Execution.call(run, model: model)
        assert_equal "no_evidence", result.status
        assert_equal "workflow_abstained", run.reload.error_code
        assert_equal "incomplete", run.messages.find_by!(role: "assistant").state
        assert_not_includes result.text, "120 demonstration units"
      end
      assert run.model_attempts.all? { |attempt| attempt.state == "settled" && attempt.actual_output_tokens }
    end
  end

  private

  def submit(**options)
    Agent::Lifecycle.submit!(user: @user, query: "Summarize original Alpha.", request_key: SecureRandom.uuid,
      workflow: Agent::EarningsWorkflow::ID, query_mode: "latest_earnings", evidence_mode: "fixture",
      enqueue: false, **@scope.symbolize_keys, **options)
  end

  def answer
    Agent::EarningsWorkflow.answer(JSON.generate(@answer), sources: [@source], scope: @scope,
      event: Agent::EarningsWorkflow.fixture_event)
  end

  def failure(&block)
    assert_raises(Research::Error, &block)
  end
end
