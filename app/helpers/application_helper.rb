module ApplicationHelper
  def current_path?(path)
    "active" if current_page?(path)
  end

  def shell_nav_link(label, path, icon, active: current_page?(path))
    link_to path, class: class_names("shell-nav", "is-active": active),
                  title: label, aria: { label: label, current: active ? "page" : nil } do
      safe_join([fa_icon(icon, aria: { hidden: true }), content_tag(:span, label, class: "sidebar-label")])
    end
  end

  def shell_page_context
    {
      "welcome" => "Overview",
      "portfolio_demos" => "Portfolio analytics",
      "research_demos" => "Research policy lab",
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
