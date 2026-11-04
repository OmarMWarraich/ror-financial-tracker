require "date"
require "json"

class ProjectKnowledge
  DEFAULT_PATH = File.expand_path("../config/project_knowledge.json", __dir__).freeze
  STATUSES = %w[verified_fact user_decision open_question implemented].freeze
  STOP_WORDS = %w[a an and are as be for from how in is it of on or the this to what with].freeze
  FIELDS = %w[id title aliases summary status updated_on sources].freeze

  def initialize(path: DEFAULT_PATH)
    @records = JSON.parse(File.read(path))
    validate!
  end

  def search(query, limit: 5)
    raise ArgumentError, "Query must be a non-empty string" unless query.is_a?(String) && !query.strip.empty?
    raise ArgumentError, "Limit must be an integer between 1 and 10" unless limit.is_a?(Integer) && (1..10).cover?(limit)

    terms = tokens(query) - STOP_WORDS
    raise ArgumentError, "Query must contain a searchable word" if terms.empty?

    @records.filter_map do |record|
      headings = tokens([record["id"], record["title"], *record["aliases"]].join(" "))
      body = tokens(record["summary"])
      matches = terms & (headings + body)
      next if matches.empty?

      score = matches.length * 10 + (terms & headings).length
      score += 5 if record["aliases"].any? { |name| tokens(name) == terms }
      [score, record]
    end.sort_by { |score, record| [-score, record["id"]] }
      .first(limit)
      .map do |score, record|
        record.reject { |key, _| key == "aliases" }.merge("score" => score)
      end
  end

  private

  def tokens(text)
    text.downcase.scan(/[a-z0-9]+/).uniq
  end

  def validate!
    raise ArgumentError, "Knowledge store must be an array" unless @records.is_a?(Array)

    ids = []
    @records.each do |record|
      unless record.is_a?(Hash) && record.keys.sort == FIELDS.sort
        raise ArgumentError, "Knowledge records must contain exactly: #{FIELDS.join(', ')}"
      end
      %w[id title summary status updated_on].each do |field|
        unless record[field].is_a?(String) && !record[field].strip.empty?
          raise ArgumentError, "Knowledge field #{field} must be a non-empty string"
        end
      end
      %w[aliases sources].each do |field|
        unless record[field].is_a?(Array) && record[field].all? { |value| value.is_a?(String) && !value.strip.empty? }
          raise ArgumentError, "Knowledge field #{field} must be an array of non-empty strings"
        end
      end
      raise ArgumentError, "Knowledge record requires a source" if record["sources"].empty?
      raise ArgumentError, "Unknown knowledge status: #{record['status']}" unless STATUSES.include?(record["status"])
      raise ArgumentError, "Knowledge date must use YYYY-MM-DD" unless record["updated_on"].match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(record["updated_on"])
      raise ArgumentError, "Duplicate knowledge id: #{record['id']}" if ids.include?(record["id"])

      ids << record["id"]
    end
  end
end
