ENV["RAILS_ENV"] ||= "test"
require_relative "../../config/environment"
require "minitest/autorun"

class UiComponentsTest < Minitest::Test
  def setup
    @view = ApplicationController.new.view_context
  end

  def test_button_preserves_submission_and_accessibility_attributes
    html = @view.render_button("Confirm", type: :submit, name: "commit", value: "confirm",
                              disabled: true, id: "confirm", aria: { label: "Confirm exact terms" },
                              data: { action: "test#confirm" })
    button = Nokogiri::HTML.fragment(html).at_css("button")
    assert_equal "submit", button["type"]
    assert_equal "commit", button["name"]
    assert_equal "confirm", button["value"]
    assert button.key?("disabled")
    assert_equal "confirm", button["id"]
    assert_equal "Confirm exact terms", button["aria-label"]
    assert_equal "test#confirm", button["data-action"]
  end

  def test_link_keeps_turbo_attributes_and_escapes_text
    html = @view.render_button("<script>alert(1)</script>", as: :link, href: "/users/sign_out",
                              data: { turbo_method: :delete, turbo_confirm: "Confirm?" })
    link = Nokogiri::HTML.fragment(html).at_css("a")
    assert_equal "/users/sign_out", link["href"]
    assert_equal "delete", link["data-turbo-method"]
    assert_equal "Confirm?", link["data-turbo-confirm"]
    assert_empty link.css("script")
    assert_equal "<script>alert(1)</script>", link.text.strip
  end

  def test_default_button_is_not_an_accidental_form_submission
    html = @view.render_button("Toggle")
    assert_equal "button", Nokogiri::HTML.fragment(html).at_css("button")["type"]
    assert_raises(ArgumentError) { @view.render_button("Unsupported", variant: :unknown) }
    assert_raises(ArgumentError) { @view.render_button("Unsupported", as: :input) }
  end

  def test_card_is_fluid_and_preserves_region_metadata
    html = @view.render_card(title: "Summary", body: "Body", id: "summary", aria: { label: "Account summary" })
    card = Nokogiri::HTML.fragment(html).at_css("div")
    assert_equal "summary", card["id"]
    assert_equal "Account summary", card["aria-label"]
    assert_includes card["class"].split, "w-full"
    refute_includes card["class"], "350px"
    assert_equal "Summary", card.at_css("h2").text
  end

  def test_badge_and_alert_preserve_attributes
    badge = Nokogiri::HTML.fragment(@view.render_badge("Fictional", id: "origin", data: { testid: "origin" })).at_css("span")
    assert_equal "origin", badge["id"]
    assert_equal "origin", badge["data-testid"]
    html = @view.render_alert(title: "Saved", description: "Done", variant: :success, icon: false,
                              role: "status", data: { controller: "alert" })
    alert = Nokogiri::HTML.fragment(html).at_css("div")
    assert_equal "status", alert["role"]
    assert_equal "alert", alert["data-controller"]
    assert_empty alert.css("svg")
  end

  def test_tailwind_build_contains_real_shell_styles_not_source_directives
    css = File.read(Rails.root.join("app/assets/builds/tailwind.css"))
    assert_includes css, "tailwindcss v3.4.19"
    assert_includes css, ".shell-sidebar"
    assert_includes css, ".search-toolbar"
    assert_includes css, 'data-navigation-open'
    assert_includes css, ".grey"
    assert_match(/color-scheme:\s*dark/, css)
    assert_includes css, "var(--canvas)"
    assert_includes css, ".theme-select"
    refute_includes css, "@apply"
    refute_includes css, '@import "ui.css"'
    assert_nil Rails.application.config.assets.css_compressor
  end
end
