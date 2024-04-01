module ApplicationHelper
  def current_path?(path)
    "active" if current_page?(path)
  end
end
