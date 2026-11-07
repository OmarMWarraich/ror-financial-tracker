require "test_helper"

class ResearchChatTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @previous = ENV["RESEARCH_CHAT_ENABLED"]
    ENV["RESEARCH_CHAT_ENABLED"] = "1"
    @owners = []
    @user = owner
  end

  teardown do
    @previous ? ENV["RESEARCH_CHAT_ENABLED"] = @previous : ENV.delete("RESEARCH_CHAT_ENABLED")
    @owners.each do |user|
      user.with_lock do
        ResearchChatSession.where(user: user).delete_all
        ResearchToolAttempt.where(user: user).delete_all
        ResearchMessage.where(user: user).delete_all
        ResearchModelAttempt.where(user: user).delete_all
        ResearchAgentRun.where(user: user).delete_all
        ResearchConversation.where(user: user).delete_all
      end
      user.destroy!
    end
  end

  test "chat requires login and operator feature flag and retains ordinary non-JavaScript forms" do
    get research_chats_path
    assert_redirected_to new_user_session_path
    sign_in @user
    ENV["RESEARCH_CHAT_ENABLED"] = "0"
    get research_chats_path
    assert_response :not_found
    ENV["RESEARCH_CHAT_ENABLED"] = "1"
    get research_chats_path
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "form[data-turbo=false] textarea[required]"
    assert_select "input[name='research_chat[request_key]']"
    assert_equal 1, @user.research_chat_sessions.count
  end

  test "explicit fixture submission deduplicates tabs and reload never enqueues while answer state is canonical" do
    sign_in @user
    input = { question: "Original Alpha question <script>unsafeMarkup()</script>", request_key: SecureRandom.uuid }
    jobs = []
    ResearchAgentJob.stub(:perform_async, ->(id) { jobs << id; "original-offline-job" }) do
      2.times do
        post research_chats_path, params: { research_chat: input }
        assert_response :see_other
      end
      run = @user.research_agent_runs.first
      assert_equal [run.id], jobs
      get research_chat_path(run.conversation_id)
      assert_select "script", text: /unsafeMarkup/, count: 0
      Research::Agent::Execution.call(run)
      2.times { get snapshot_research_chat_path(run.conversation_id); assert_response :success }
      assert_equal [run.id], jobs
      assert_equal 2, run.messages.count
      assert run.messages.find_by!(role: "assistant").sources.all? { |source| source["synthetic"] && !source.key?("text") }
      assert_select "[data-run-state=completed]"
      assert_select "a[href^='https://example.invalid']", count: 0
      assert_select "details summary", text: "Sources and temporal uncertainty"
    end
  end

  test "cross-owner page snapshot stop and expired evidence cannot expose chat" do
    run = submit(owner)
    sign_in @user
    get research_chats_path
    get research_chat_path(run.conversation_id)
    assert_response :not_found
    get snapshot_research_chat_path(run.conversation_id)
    assert_response :not_found
    post stop_research_chat_path(run.conversation_id), params: { run_id: run.id }
    assert_response :not_found
    own = submit(@user)
    travel 2.days do
      get research_chat_path(own.conversation_id)
      assert_response :success
      get snapshot_research_chat_path(own.conversation_id)
      assert_response :success
      assert_includes response.body, "chat_retention_expired"
      assert_not_includes response.body, "Original fixture question."
    end
  end

  test "snapshot polling cannot renew an expired chat lease but an explicit visit can" do
    sign_in @user
    get research_chats_path
    run = submit(@user)
    travel 31.minutes do
      get snapshot_research_chat_path(run.conversation_id)
      assert_response :unauthorized
      assert_equal 1, @user.research_chat_sessions.count
      assert_not_includes response.body, "Original fixture question."
      get research_chat_path(run.conversation_id)
      assert_response :success
      assert_equal 2, @user.research_chat_sessions.count
      get snapshot_research_chat_path(run.conversation_id)
      assert_response :success
    end
  end

  test "Redis disconnect outage cannot prevent ordinary logout and lease revocation" do
    sign_in @user
    get research_chats_path
    lease = @user.research_chat_sessions.last
    remote = Object.new
    remote.define_singleton_method(:where) { |**| raise Redis::CannotConnectError, "original offline disconnect" }
    ActionCable.server.stub(:remote_connections, remote) do
      delete destroy_user_session_path
      assert_response :see_other
    end
    assert lease.reload.revoked_at
    get research_chats_path
    assert_redirected_to new_user_session_path
  end

  test "stop is owner-scoped terminal and logout revokes the browser lease" do
    sign_in @user
    get research_chats_path
    lease = @user.research_chat_sessions.last
    run = submit(@user)
    post stop_research_chat_path(run.conversation_id), params: { run_id: run.id }
    assert_response :see_other
    assert_equal "cancelled", run.reload.state
    delete destroy_user_session_path
    assert lease.reload.revoked_at
    assert_not lease.valid_access?
    get snapshot_research_chat_path(run.conversation_id)
    assert_redirected_to new_user_session_path
  end

  test "workflow and lowered limits are server controlled and cannot be raised in followups" do
    sign_in @user
    input = { question: "Original Alpha question.", request_key: SecureRandom.uuid, workflow: "latest_earnings_v1",
      preferences: { output_tokens: "1500", tools: "3", seconds: "60" } }
    ResearchAgentJob.stub(:perform_async, ->(*) { "original-offline-job" }) do
      post research_chats_path, params: { research_chat: input }
      run = @user.research_agent_runs.first
      assert_equal "latest_earnings_v1", run.workflow_version
      assert_equal [1500, 3, 60], run.limits.values_at("output_tokens", "tools", "seconds")
      Research::Agent::Execution.call(run)
      [["arbitrary-user-prompt", "1200"], ["latest_earnings_v1", "4096"]].each do |workflow, output|
        post research_chats_path, params: { research_chat: input.merge(request_key: SecureRandom.uuid,
          conversation_id: run.conversation_id, workflow: workflow, preferences: { output_tokens: output }) }
        assert_response :see_other
        assert_equal 1, @user.research_agent_runs.count
      end
    end
  end

  test "stream batches invalidate only canonical state and outage cannot corrupt completed publication" do
    run = submit(@user)
    updates = Research::Chat::Updates.new(run)
    messages = []
    ActionCable.server.stub(:broadcast, ->(stream, message) { messages << [stream, message] }) do
      updates.call({ "type" => "run.started", "data" => { "text" => "original-private-untrusted-input" } })
      20.times { updates.call({ "type" => "text.delta", "data" => { "text" => "original-private-untrusted-input" } }) }
      updates.call({ "type" => "run.completed" })
    end
    assert_equal 2, messages.size
    assert messages.all? { |stream, payload| stream == Research::Chat.stream(run.conversation) && payload == { "version" => 1, "refresh" => true } }
    ActionCable.server.stub(:broadcast, ->(*) { raise Redis::CannotConnectError, "original offline failure" }) do
      Research::Agent::Execution.call(run, events: updates.method(:call))
    end
    assert_equal "completed", run.reload.state
    assert run.messages.find_by!(role: "assistant").content.present?
  end

  private

  def owner
    User.create!(email: "original-chat-#{SecureRandom.uuid}@example.test", password: "original-fixture-password").tap { |user| @owners << user }
  end

  def submit(user)
    Research::Agent::Lifecycle.submit!(user: user, query: "Original fixture question.", request_key: SecureRandom.uuid,
      listing_identity: "SYNTH:ALPHA", fiscal_year: 2026, fiscal_quarter: 3, enqueue: false)
  end
end
