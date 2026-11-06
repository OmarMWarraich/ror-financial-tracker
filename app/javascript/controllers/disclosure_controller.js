import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  outside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  escape(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.close()
    this.element.querySelector("summary").focus()
  }

  close() {
    this.element.open = false
  }
}
