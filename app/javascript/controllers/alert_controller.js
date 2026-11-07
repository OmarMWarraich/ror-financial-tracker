import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.classList.remove("toast-dismissing")
    this.dismissTimer = setTimeout(() => this.dismiss(), 3000)
  }

  disconnect() {
    clearTimeout(this.dismissTimer)
    clearTimeout(this.removeTimer)
  }

  dismiss() {
    if (this.element.classList.contains("toast-dismissing")) return

    clearTimeout(this.dismissTimer)
    this.element.classList.add("toast-dismissing")
    this.removeTimer = setTimeout(() => this.remove(), 200)
  }

  remove() {
    this.disconnect()
    this.element.remove()
  }
}
