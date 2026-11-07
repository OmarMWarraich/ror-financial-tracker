module Research
  class SyntheticSource
    def call(request, before_request: nil, api_key: nil)
      version = request.fixture_version
      text = version == "v1" ? "Synthetic Alpha reported revenue of 120 demonstration units." :
                              "Correction: Synthetic Alpha reported revenue of 125 demonstration units."
      parts = [
        { "text" => text, "speaker" => "Fictional Chief Executive", "speaker_role" => "CEO",
          "section" => "prepared_remarks", "turn_index" => 0, "start_seconds" => 0.0, "end_seconds" => 12.0 },
        { "text" => "This original fixture is not a real issuer, investment recommendation, or provider transcript.",
          "speaker" => nil, "section" => "synthetic_disclaimer", "turn_index" => 1 }
      ]
      now = Time.current
      {
        parts: parts, metadata: { "synthetic" => true, "provider_event_id" => "original-alpha-2026-q3",
                                "fiscal_year" => 2026, "fiscal_quarter" => 3, "listing_identity" => "SYNTH:ALPHA",
                                "source_kind" => request.source_kind, "fixture_version" => version },
        event_at: Time.iso8601("2026-10-28T18:00:00Z"),
        published_at: Time.iso8601("2026-10-28T19:00:00Z"),
        known_at: Time.iso8601("2026-10-28T19:00:00Z"), received_at: now
      }
    end
  end
end
