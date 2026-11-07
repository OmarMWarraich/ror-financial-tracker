require "tiktoken_ruby"

module Research
  class Chunker
    PREPROCESSING = "utf8-nfc-lines-v1"
    VERSION = "cl100k-speaker-800-overlap50-v1"
    MAX_BYTES = 262_144
    SECRET = /(?:-----BEGIN [A-Z ]*PRIVATE KEY-----|\bBearer\s+[A-Za-z0-9._-]{12,}|\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{16,}|\beq_[A-Za-z0-9_-]{16,}|\b(?:api[_ -]?key|account[_ -]?key|password|access[_ -]?token)["']?\s*[:=]\s*\S+)/i

    def self.normalize(parts, metadata:, forbidden: [])
      unless parts.is_a?(Array) && parts.size.between?(1, 100) && metadata.is_a?(Hash)
        raise Error.new("invalid_source_content")
      end
      content = +""
      serialized = JSON.generate([parts, metadata])
      raise Error.new("source_too_large") if serialized.bytesize > MAX_BYTES
      if serialized.match?(SECRET) || forbidden.any? { |secret| secret.present? && serialized.include?(secret) }
        raise Error.new("credential_content_rejected")
      end
      segments = parts.map.with_index do |part, index|
        raise Error.new("invalid_source_content") unless part.is_a?(Hash)
        text = part.fetch("text")
        unless text.is_a?(String) && text.valid_encoding? && text.encoding == Encoding::UTF_8 &&
               text.present? && !text.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F]/) &&
               [part["speaker"], part["speaker_role"], part["section"]].all? { |value|
                 value.nil? || (value.is_a?(String) && value.length <= 256)
               }
          raise Error.new("invalid_source_content")
        end
        if text.match?(SECRET) || forbidden.any? { |secret| secret.present? && text.include?(secret) }
          raise Error.new("credential_content_rejected")
        end
        text = text.unicode_normalize(:nfc).gsub("\r\n", "\n").gsub("\r", "\n")
        content << "\n" unless index.zero?
        start = content.length
        line = content.count("\n") + 1
        content << text
        raise Error.new("source_too_large") if content.bytesize > MAX_BYTES
        part.except("text").merge("start_char" => start, "end_char" => content.length, "start_line" => line)
      end
      data = metadata.merge("segments" => segments, "preprocessing_version" => PREPROCESSING)
      # Receipt time is deliberately excluded: unchanged source content is the same revision on refetch.
      key = Digest::SHA256.hexdigest(JSON.generate(canonical([content, data])))
      { content: content, source_metadata: data, source_revision: key }
    rescue KeyError, JSON::GeneratorError
      raise Error.new("invalid_source_content")
    end

    def self.canonical(value)
      case value
      when Hash then value.sort_by { |key, _| key.to_s }.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
    private_class_method :canonical

    def initialize
      @encoding = Tiktoken.get_encoding("cl100k_base")
    end

    def tokens(text)
      @encoding.encode_ordinary(text).length
    end

    def call(revision)
      result = []
      revision.source_metadata.fetch("segments").each do |segment|
        text = revision.content[segment.fetch("start_char")...segment.fetch("end_char")]
        start = 0
        while start < text.length
          length = prefix_length(text[start..], 800)
          raise Error.new("invalid_source_content") if length.zero?
          piece = text[start, length]
          line = segment.fetch("start_line") + text[0...start].count("\n")
          result << {
            position: result.length, content: piece, token_count: tokens(piece),
            start_char: segment.fetch("start_char") + start, end_char: segment.fetch("start_char") + start + length,
            start_line: line, end_line: line + piece.count("\n"), speaker: segment["speaker"],
            source_metadata: segment.except("start_char", "end_char", "start_line")
          }
          break if start + length == text.length
          overlap = [suffix_length(piece, 50), length - 1].min
          start += length - overlap
        end
      end
      raise Error.new("source_token_limit") if result.sum { |part| part[:token_count] } > 20_000
      result
    end

    private

    def prefix_length(text, limit)
      largest_length(text.length) { |size| tokens(text[0, size]) <= limit }
    end

    def suffix_length(text, limit)
      largest_length(text.length) { |size| tokens(size.zero? ? "" : text[-size, size]) <= limit }
    end

    def largest_length(length)
      low = 0
      high = length
      while low < high
        middle = (low + high + 1) / 2
        yield(middle) ? low = middle : high = middle - 1
      end
      low
    end
  end
end
