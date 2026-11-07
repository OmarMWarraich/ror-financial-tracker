module ResearchChatsHelper
  def research_markdown(text)
    html = Kramdown::Document.new(text, auto_ids: false, parse_block_html: false,
      math_engine: nil, syntax_highlighter: nil).to_html
    sanitize(html, tags: %w[p br strong em ul ol li blockquote pre code h2 h3 h4 hr], attributes: [])
  end

  def research_citation_url(value)
    return unless value.is_a?(String) && value.bytesize <= 2048
    uri = URI.parse(value)
    value if uri.scheme == "https" && uri.host == "equibles.com" && uri.port == 443 &&
      uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
  rescue URI::InvalidURIError
    nil
  end
end
