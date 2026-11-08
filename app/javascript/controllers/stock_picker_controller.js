import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "panel", "list", "status", "more"]
  static values = { url: String }

  connect() {
    this.generation = (this.generation || 0) + 1
    this.index = -1
    this.currentQuery = null
    this.selectedLabel = this.inputTarget.value
    this.disconnected = false
  }

  disconnect() {
    this.disconnected = true
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  open() {
    this.panelTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.inputTarget.select()
    if (this.currentQuery === null) this.load("", 0)
  }

  close() {
    clearTimeout(this.timer)
    this.abort?.abort()
    this.generation += 1
    this.loading = false
    this.currentQuery = null
    this.inputTarget.value = this.selectedLabel
    this.panelTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.index = -1
  }

  outside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  blur(event) {
    if (event.relatedTarget && !this.element.contains(event.relatedTarget)) this.close()
  }

  schedule() {
    clearTimeout(this.timer)
    this.abort?.abort()
    this.generation += 1
    this.listTarget.innerHTML = ""
    this.moreTarget.hidden = true
    this.index = -1
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.timer = setTimeout(() => this.load(this.inputTarget.value.trim(), 0), 500)
  }

  search(event) {
    event.preventDefault()
    clearTimeout(this.timer)
    this.load(this.inputTarget.value.trim(), 0)
  }

  more() {
    if (this.nextOffset !== null && !this.loading) this.load(this.currentQuery, this.nextOffset)
  }

  async load(query, offset) {
    this.abort?.abort()
    const abort = new AbortController()
    this.abort = abort
    const generation = ++this.generation
    this.loading = true
    this.panelTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.statusTarget.textContent = "Loading US stock listings..."
    this.moreTarget.disabled = true
    if (offset === 0) {
      this.listTarget.innerHTML = ""
      this.moreTarget.hidden = true
      this.index = -1
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
    const timeout = setTimeout(() => abort.abort(), 10000)
    try {
      const url = new URL(this.urlValue, location.origin)
      url.search = new URLSearchParams({ query, offset })
      const response = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store", signal: abort.signal })
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`)
      if (typeof result.html !== "string" || (result.next_offset !== null && !Number.isInteger(result.next_offset))) {
        throw new Error("Invalid listing response")
      }
      if (this.disconnected || generation !== this.generation) return
      this.listTarget.insertAdjacentHTML("beforeend", result.html)
      this.currentQuery = query
      this.nextOffset = result.next_offset
      this.moreTarget.hidden = this.nextOffset === null
      const count = this.options().length
      this.statusTarget.textContent = count
        ? `${count} US stocks shown. ${this.nextOffset === null ? "End of results." : "Load more to continue."}`
        : `No matching US stocks on this page.${this.nextOffset === null ? "" : " Load more to continue."}`
    } catch (error) {
      if (!this.disconnected && generation === this.generation) {
        this.statusTarget.textContent = `Stock search unavailable: ${error.message}. Submit the search to retry.`
      }
    } finally {
      clearTimeout(timeout)
      if (generation === this.generation) {
        this.loading = false
        this.moreTarget.disabled = false
      }
    }
  }

  options() {
    return Array.from(this.listTarget.querySelectorAll('[role="option"]'))
  }

  key(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      this.panelTarget.hidden = false
      this.inputTarget.setAttribute("aria-expanded", "true")
      const options = this.options()
      if (!options.length) return
      this.index = this.index < 0 ? (event.key === "ArrowDown" ? 0 : options.length - 1) :
        (this.index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length
      options.forEach((option, index) => option.setAttribute("aria-selected", String(index === this.index)))
      this.inputTarget.setAttribute("aria-activedescendant", options[this.index].id)
      options[this.index].scrollIntoView({ block: "nearest" })
    } else if (event.key === "Enter" && this.index >= 0 && !this.panelTarget.hidden) {
      event.preventDefault()
      this.choose({ preventDefault() {}, currentTarget: this.options()[this.index] })
    }
  }

  choose(event) {
    event.preventDefault()
    this.close()
    this.dispatch("select", { detail: { ticker: event.currentTarget.dataset.stockPickerTicker } })
  }
}
