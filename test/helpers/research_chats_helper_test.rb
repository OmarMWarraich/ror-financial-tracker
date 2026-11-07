require "test_helper"

class ResearchChatsHelperTest < ActionView::TestCase
  tests ResearchChatsHelper

  test "Markdown formatting survives without raw HTML script image attributes or model-authored links" do
    html = research_markdown("**Original**\n\n<script>alert(1)</script><img src=x onerror=alert(1)>\n\n[unsafe](javascript:alert(1))\n\n[external](https://other.test/)")
    assert_includes html, "<strong>Original</strong>"
    assert_empty Nokogiri::HTML.fragment(html).css("script,img,a,[onerror]")
    %w[javascript: href=].each { |unsafe| assert_not_includes html, unsafe }
  end

  test "citations allow only fixed HTTPS authority without credentials query fragments or redirects" do
    assert_equal "https://equibles.com/stocks/MSFT", research_citation_url("https://equibles.com/stocks/MSFT")
    %w[http://equibles.com https://evil.test https://equibles.com.evil.test
      https://secret@equibles.com https://equibles.com/?apiKey=original
      javascript:alert(1) https://equibles.com:444/stocks/MSFT https://equibles.com/stocks/MSFT#x].each do |url|
      assert_nil research_citation_url(url), url
    end
  end
end
