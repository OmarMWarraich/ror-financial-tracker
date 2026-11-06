import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["sidebar", "workspace", "menuButton", "collapseButton", "overlay"]

  connect() {
    this.mobileQuery = window.matchMedia("(max-width: 1023px)")
    this.resize = () => this.close()
    this.mobileQuery.addEventListener("change", this.resize)
    this.element.dataset.shellReady = "true"
    this.close()
  }

  disconnect() {
    this.mobileQuery.removeEventListener("change", this.resize)
    this.reset()
    delete this.element.dataset.shellReady
  }

  open() {
    if (!this.mobileQuery.matches) return
    this.element.dataset.navigationOpen = "true"
    this.sidebarTarget.inert = false
    this.sidebarTarget.removeAttribute("aria-hidden")
    this.sidebarTarget.setAttribute("role", "dialog")
    this.sidebarTarget.setAttribute("aria-modal", "true")
    this.menuButtonTarget.setAttribute("aria-expanded", "true")
    this.workspaceTarget.inert = true
    this.sidebarTarget.querySelector("a, button").focus()
  }

  close() {
    const wasOpen = this.element.dataset.navigationOpen === "true"
    this.reset()
    this.sidebarTarget.inert = this.mobileQuery.matches
    if (this.mobileQuery.matches) this.sidebarTarget.setAttribute("aria-hidden", "true")
    if (wasOpen) this.menuButtonTarget.focus()
  }

  reset() {
    delete this.element.dataset.navigationOpen
    this.sidebarTarget.inert = false
    this.sidebarTarget.removeAttribute("aria-hidden")
    this.sidebarTarget.removeAttribute("role")
    this.sidebarTarget.removeAttribute("aria-modal")
    this.workspaceTarget.inert = false
    this.menuButtonTarget.setAttribute("aria-expanded", "false")
  }

  toggleCollapsed() {
    if (this.mobileQuery.matches) return
    const collapsed = this.element.dataset.sidebarCollapsed !== "true"
    this.element.dataset.sidebarCollapsed = String(collapsed)
    this.collapseButtonTarget.setAttribute("aria-expanded", String(!collapsed))
    this.collapseButtonTarget.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar")
    this.sidebarTarget.querySelectorAll(".nav-group").forEach(group => { group.open = true })
  }

  escape(event) {
    if (this.element.dataset.navigationOpen !== "true") return
    event.preventDefault()
    this.close()
  }

  trapFocus(event) {
    if (event.key !== "Tab" || this.element.dataset.navigationOpen !== "true") return
    const focusable = [...this.sidebarTarget.querySelectorAll("a[href], button, summary")]
      .filter(element => element.getClientRects().length > 0)
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  beforeCache() {
    this.close()
  }
}
