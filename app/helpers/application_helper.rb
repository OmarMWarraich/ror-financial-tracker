module ApplicationHelper
  def market_chart_points(history, sessions)
    rows = history.fetch("points").last(sessions)
    return nil if rows.length < 2
    values = rows.map { |row| row.fetch("close").to_f }
    low, high = values.minmax
    span = high - low
    path = values.each_with_index.map do |value, index|
      x = (index * 700.0 / (values.length - 1)).round(2)
      y = span.zero? ? 100 : (180 - (value - low) / span * 160).round(2)
      "#{x},#{y}"
    end.join(" ")
    { path: path, first: rows.first["date"], last: rows.last["date"], low: low, high: high,
      points: rows.map { |row| { date: row["date"], close: row["close"] } } }
  end

  def current_path?(path)
    "active" if current_page?(path)
  end

  def shell_nav_link(label, path, icon, active: current_page?(path))
    link_to path, class: class_names("shell-nav", "is-active": active),
                  title: label, data: { turbo_prefetch: false }, aria: { label: label, current: active ? "page" : nil } do
      safe_join([fa_icon(icon, aria: { hidden: true }), content_tag(:span, label, class: "sidebar-label")])
    end
  end

  def shell_page_context
    {
      "welcome" => "Overview",
      "portfolio_demos" => "Portfolio analytics",
      "market_dashboards" => "Dashboard",
      "research_demos" => "Research policy lab",
      "research_chats" => "Research chat",
      "broker_connections" => "Private connections",
      "equibles_evidence" => "Private Equibles evidence",
      "deposit_information" => "Deposit information gates",
      "sandbox_accounts" => "Synthetic sandbox",
      "sandbox_mandates" => "Synthetic sandbox",
      "sessions" => "Sign in",
      "registrations" => action_name == "edit" ? "Edit Profile" : "Create account",
      "passwords" => "Password recovery",
      "confirmations" => "Account confirmation",
      "unlocks" => "Account recovery",
      "users" => action_name == "my_portfolio" ? "My Portfolio" : "My Friends"
    }.fetch(controller_name, "Workspace")
  end
end
