require "test_helper"

class ResearchChunkerTest < ActiveSupport::TestCase
  test "UTF8 boundaries tokens overlap and attribution retain exact source ranges" do
    text = ("Original demonstration revenue grew. \u{1F984}\n" * 300)
    normalized = Research::Chunker.normalize(
      [{ "text" => text, "speaker" => "Fictional executive", "section" => "remarks", "turn_index" => 0 },
       { "text" => "Original questions\r\nOriginal answers", "speaker" => nil, "section" => "qa", "turn_index" => 1 }],
      metadata: { "fiscal_year" => 2026, "fiscal_quarter" => 3 }
    )
    row = ResearchRevision.new(normalized)
    chunker = Research::Chunker.new
    chunks = chunker.call(row)
    assert_operator chunks.size, :>, 3
    chunks.each do |chunk|
      assert chunk[:content].valid_encoding?
      assert_equal row.content[chunk[:start_char]...chunk[:end_char]], chunk[:content]
      assert_equal chunker.tokens(chunk[:content]), chunk[:token_count]
      assert_operator chunk[:token_count], :<=, 800
      assert_equal row.content[0...chunk[:start_char]].count("\n") + 1, chunk[:start_line]
    end
    remarks = chunks.select { |part| part[:source_metadata]["section"] == "remarks" }
    assert_equal 0, remarks.first[:start_char]
    assert_equal text.length, remarks.last[:end_char]
    remarks.each_cons(2) do |first, second|
      overlap = row.content[second[:start_char]...first[:end_char]]
      assert_operator chunker.tokens(overlap), :<=, 50
      assert_operator second[:start_char], :>, first[:start_char]
      assert_operator second[:start_char], :<=, first[:end_char]
      assert_equal "Fictional executive", second[:speaker]
    end
    assert_nil chunks.last[:speaker]
    assert_equal "qa", chunks.last[:source_metadata]["section"]
    assert_equal 2026, row.source_metadata["fiscal_year"]
    assert_includes row.content, "Original questions\nOriginal answers"
  end

  test "normalization is stable but corrections produce a different revision key" do
    parts = [{ "text" => "Original statement", "speaker" => "Fictional analyst" }]
    first = Research::Chunker.normalize(parts, metadata: { "corrections" => [] })
    assert_equal first, Research::Chunker.normalize(parts, metadata: { "corrections" => [] })
    correction = Research::Chunker.normalize(parts, metadata: { "corrections" => [{ "note" => "Original correction" }] })
    assert_equal first[:content], correction[:content]
    assert_not_equal first[:source_revision], correction[:source_revision]
    reordered = Research::Chunker.normalize(parts, metadata: { "nested" => { "b" => 2, "a" => 1 } })
    ordered = Research::Chunker.normalize(parts, metadata: { "nested" => { "a" => 1, "b" => 2 } })
    assert_equal ordered[:source_revision], reordered[:source_revision]
  end

  test "empty malformed oversized and credential-bearing content is rejected" do
    ["", " \n", "bad\u0000text", "\xFF".b, "api_key: forbidden-secret",
     "sk-proj-012345678901234567890", "a" * (Research::Chunker::MAX_BYTES + 1)].each do |text|
      assert_raises(Research::Error) { Research::Chunker.normalize([{ "text" => text }], metadata: {}) }
    end
    error = assert_raises(Research::Error) do
      Research::Chunker.normalize([{ "text" => "Original source contains known-private-key" }],
                                  metadata: {}, forbidden: ["known-private-key"])
    end
    assert_equal "credential_content_rejected", error.code
    assert_raises(Research::Error) { Research::Chunker.normalize([nil], metadata: {}) }
    assert_raises(Research::Error) { Research::Chunker.normalize([], metadata: {}) }
    assert_raises(Research::Error) {
      Research::Chunker.normalize([{ "text" => '{"account_key":"original-secret"}' }], metadata: {})
    }
  end

  test "the embedding token allowance includes overlap and rejects overlong sources" do
    normalized = Research::Chunker.normalize([{ "text" => " original" * 21_000 }], metadata: {})
    assert_equal "source_token_limit", assert_raises(Research::Error) {
      Research::Chunker.new.call(ResearchRevision.new(normalized))
    }.code
  end
end
