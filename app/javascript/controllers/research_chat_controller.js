import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["frame", "status"]
  static values = { conversation: Number, snapshot: String }

  connect() {
    this.accessDenied = false
    this.paused = false
    this.disposing = false
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "ResearchChatChannel", conversation_id: this.conversationValue },
      {
        connected: () => { this.connected = true; this.refresh() },
        disconnected: ({ willAttemptReconnect }) => {
          this.connected = false
          if (this.accessDenied || this.disposing) return
          if (!willAttemptReconnect && !this.paused) this.denyAccess("Chat connection closed. Reload or sign in again.")
          else this.clear("Disconnected. Reloading saved state without resubmitting.")
        },
        rejected: () => this.denyAccess("Research subscription rejected. Reload or sign in again."),
        received: (data) => { if (data.version === 1 && data.refresh) this.scheduleRefresh() }
      }
    )
    this.poll = setInterval(() => this.refresh(), 5000)
  }

  disconnect() {
    this.disposing = true
    clearInterval(this.poll)
    clearTimeout(this.pending)
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  scheduleRefresh() {
    if (!this.pending) this.pending = setTimeout(() => { this.pending = null; this.refresh() }, 300)
  }

  refresh() {
    if (this.accessDenied || document.hidden || this.loading || !this.hasFrameTarget) return
    this.loading = true
    const focused = document.activeElement
    this.focusId = this.frameTarget.contains(focused) ? focused.id : null
    if (this.frameTarget.src) this.frameTarget.reload()
    else this.frameTarget.src = this.snapshotValue
  }

  loaded() {
    if (this.accessDenied) {
      this.clear(this.accessError)
      return
    }
    this.loading = false
    const runs = [...this.frameTarget.querySelectorAll("[data-run-state]")]
    const state = runs.at(-1)?.dataset.runState || "ready"
    const text = `${this.connected ? "Connected" : "Polling saved state"} / ${state}. Reloads never resubmit.`
    if (this.statusTarget.textContent !== text) this.statusTarget.textContent = text
    if (this.focusId) this.frameTarget.querySelector(`#${CSS.escape(this.focusId)}`)?.focus()
  }

  missing(event) {
    event.preventDefault()
    this.denyAccess("Session or chat access expired. Reload the page or sign in again.")
  }

  denyAccess(message) {
    this.accessDenied = true
    this.accessError = message
    clearInterval(this.poll)
    clearTimeout(this.pending)
    this.consumer.disconnect()
    this.clear(message)
  }

  failed() {
    this.clear("Connection unavailable. Saved state is not resubmitted; reload when connected.")
  }

  clear(message) {
    this.loading = false
    this.frameTarget.replaceChildren()
    this.statusTarget.textContent = message
  }

  beforeCache() {
    this.clear("Reload saved research state.")
    this.disconnect()
  }

  pause() {
    this.paused = true
    this.consumer?.disconnect()
  }

  resume() {
    if (this.accessDenied) return
    this.paused = false
    this.consumer?.connect()
    this.refresh()
  }

  visibility() {
    if (document.hidden) this.pause()
    else this.resume()
  }
}
