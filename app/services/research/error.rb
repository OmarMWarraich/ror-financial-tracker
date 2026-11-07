module Research
  class Error < StandardError
    attr_reader :code, :actual_tokens

    def initialize(code, actual_tokens: nil)
      @code = code
      @actual_tokens = actual_tokens
      super(code)
    end
  end
end
