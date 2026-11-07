module Research
  module Agent
    class Events
      TYPES = %w[run.started model.started model.completed text.delta tool.started tool.completed run.completed run.no_evidence run.failed run.cancelled].freeze

      def initialize(run, sink:)
        @run, @sink = run, sink
        @sequence = 0
      end

      def emit(type, data = {})
        raise Research::Error.new("invalid_agent_event") unless TYPES.include?(type)
        @sequence += 1
        @sink&.call({ "version" => 1, "run_id" => @run.id, "sequence" => @sequence, "type" => type,
                     "at" => Time.current.utc.iso8601(6), "data" => data })
      end
    end
  end
end
