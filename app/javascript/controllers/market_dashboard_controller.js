import { Controller } from "@hotwired/stimulus"
import { emptyPreferences, readLocalPreferences, updatePreferences, validatePreferences } from "dashboard-preferences"

export default class extends Controller {
  static targets = ["board", "status", "form"]
  static values = { url: String, interval: { type: Number, default: 900000 }, enabled: { type: Boolean, default: true }, paused: { type: Boolean, default: false } }

  connect() {
    this.disconnected = false
    this.generation = (this.generation || 0) + 1
    this.busy = false
    this.stopped = this.pausedValue === true
    this.visibilityListener = () => this.activate()
    document.addEventListener("visibilitychange", this.visibilityListener)
    this.lastRefresh = this.hasListings() ? Date.now() : 0
    this.quoteSources = new Map(Array.from(this.boardTarget.querySelectorAll("[data-market-quote-source]"))
      .map(node => [node.dataset.marketPrice, node.dataset.marketQuoteSource]))
    this.preferences = emptyPreferences()
    this.preferencesDirty = false
    this.preferencesReady = false
    this.preferencesKey = null
    this.initializePreferences()
    this.activate()
  }

  disconnect() {
    clearTimeout(this.preferencesTimer)
    this.preferencesRestoreAbort?.abort()
    this.preferencesWriteAbort?.abort()
    document.removeEventListener("visibilitychange", this.visibilityListener)
    clearTimeout(this.timer)
    this.abortController?.abort()
    this.abortController = null
    this.busy = false
    this.disconnected = true
  }

  hasListings() {
    return this.boardTarget.querySelector("[data-market-listing]") !== null
  }

  activate() {
    clearTimeout(this.timer)
    if (document.hidden || this.disconnected || this.stopped || this.enabledValue === false) return
    const remaining = this.intervalValue - (Date.now() - this.lastRefresh)
    if (!this.hasListings() || remaining <= 0) this.refresh()
    else this.timer = setTimeout(() => this.activate(), remaining)
  }

  start(event) {
    event.preventDefault()
    if (this.busy) return
    this.stopped = false
    this.enabledValue = true
    this.refresh(true)
  }

  async refresh(rerank = false) {
    if (this.busy || this.disconnected) return
    const generation = this.generation
    const ranking = this.boardTarget.querySelector("[data-market-ranking-date]")
    const today = new Date().toISOString().slice(0, 10)
    const mode = rerank || !this.hasListings() || ranking?.dataset.marketRankingDate !== today ? "leaders" : "quotes"
    const tickers = Array.from(this.boardTarget.querySelectorAll("[data-market-listing]")).map(node => node.dataset.marketListing).join(",")
    try {
      const result = await this.request(mode, tickers)
      if (this.disconnected || generation !== this.generation) return
      let renewed = null
      if (mode === "leaders") {
        this.boardTarget.innerHTML = result.html
        this.initializePreferences()
        this.quoteSources = new Map(Array.from(this.boardTarget.querySelectorAll("[data-market-quote-source]"))
          .map(node => [node.dataset.marketPrice, node.dataset.marketQuoteSource]))
      } else renewed = this.updateQuotes(result.stocks)
      this.lastRefresh = Date.now()
      this.stopped = result.errors.length > 0
      this.statusTarget.textContent = this.stopped
        ? `Refresh incomplete: ${result.errors.join(" ")} Automatic requests paused; use manual refresh.`
        : `Equibles checked ${result.received_at}${renewed === null ? "" : `; ${renewed} listings have new source timestamps`}. Next check in15 minutes while visible. Fundamentals keep their captured dates.`
    } catch (error) {
      if (!this.disconnected && generation === this.generation) {
        this.stopped = true
        this.statusTarget.textContent = `Refresh failed: ${error.message}. Previous data is not current. Automatic requests paused.`
      }
    } finally {
      if (!this.disconnected && generation === this.generation) this.activate()
    }
  }

  async select(event) {
    event.preventDefault()
    if (this.busy) return
    const generation = this.generation
    const ticker = new FormData(event.currentTarget).get("tickers")
    const listing = Array.from(this.boardTarget.querySelectorAll("[data-market-listing]")).find(node => node.dataset.marketListing === ticker)
    try {
      const result = await this.request("detail", ticker)
      if (this.disconnected || generation !== this.generation) return
      this.boardTarget.querySelector("[data-market-detail]").innerHTML = result.html
      if (this.preferencesKey) {
        this.preferences = updatePreferences(this.preferences, { type: "select", ticker })
        this.preferencesDirty = true
        this.savePreferences()
      }
      const heading = this.boardTarget.querySelector("[data-market-detail] h3, [data-market-detail] h2")
      if (heading && listing) heading.textContent = listing.dataset.marketName
      if (result.errors.length) this.stopped = true
      this.statusTarget.textContent = result.errors.length ? result.errors.join(" ") : `Selected ${ticker}. Daily history and earnings retrieved ${result.received_at}.`
    } catch (error) {
      if (!this.disconnected && generation === this.generation) {
        this.stopped = true
        this.statusTarget.textContent = `Stock details unavailable: ${error.message}. Automatic requests paused.`
      }
    } finally {
      if (!this.disconnected && generation === this.generation) this.activate()
    }
  }

  async request(mode, tickers) {
    this.busy = true
    clearTimeout(this.timer)
    this.statusTarget.textContent = "Loading real Equibles data..."
    const abortController = new AbortController()
    this.abortController = abortController
    const timeout = setTimeout(() => abortController.abort(), 30000)
    try {
      const response = await fetch(this.urlValue, {
        method: "POST", credentials: "same-origin", cache: "no-store",
        headers: { "Accept": "application/json", "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
        body: new URLSearchParams({ mode, tickers,
          selected: this.boardTarget.querySelector("[data-market-selected]")?.dataset.marketSelected || "" }),
        signal: abortController.signal
      })
      if (response.redirected) throw new Error("Session expired; sign in again")
      const result = await response.json()
      if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`)
      return result
    } finally {
      clearTimeout(timeout)
      if (this.abortController === abortController) this.busy = false
    }
  }

  updateQuotes(stocks) {
    let renewed = 0
    for (const stock of stocks) {
      const source = stock.quote?.source_at || ""
      if (source && this.quoteSources.get(stock.ticker) !== source) renewed += 1
      this.quoteSources.set(stock.ticker, source)
      for (const node of this.boardTarget.querySelectorAll("[data-market-price]")) {
        if (node.dataset.marketPrice === stock.ticker) node.textContent = stock.quote
          ? new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(stock.quote.price) : "Unavailable"
      }
      for (const node of this.boardTarget.querySelectorAll("[data-market-timing]")) {
        if (node.dataset.marketTiming === stock.ticker) node.textContent = stock.quote
          ? `${stock.quote.delayed === true ? "Delayed quote" : "Delay not verified"} / source ${stock.quote.source_at || "Unknown"}`
          : "Quote unavailable; no current reading"
      }
    }
    return renewed
  }

  range(event) {
    const label = event.currentTarget.dataset.marketRange
    const scope = event.currentTarget.closest("[data-market-visualization]")
    this.applyRange(scope, label)
    if (this.preferencesKey && scope.closest("[data-dashboard-preferences]")) {
      this.preferences = updatePreferences(this.preferences, { type: "range", ticker: scope.dataset.marketVisualization, range: label })
      this.preferencesDirty = true
      this.savePreferences()
    }
  }

  applyRange(scope, label) {
    for (const chart of scope.querySelectorAll("[data-market-chart]")) chart.hidden = chart.dataset.marketChart !== label
    for (const button of scope.querySelectorAll("[data-market-range]")) button.setAttribute("aria-pressed", String(button.dataset.marketRange === label))
  }

  initializePreferences() {
    const node = this.boardTarget.querySelector("[data-dashboard-preferences]")
    if (!node?.dataset?.ownerScope) return
    this.preferencesStatus = node.querySelector("[data-dashboard-persistence]")
    if (this.preferencesKey) {
      this.applyPreferences()
      this.preferencesStatus.textContent = "UI preferences preserved; market data freshly fetched."
      return
    }
    this.preferencesKey = `dashboard-ui:v1:${node.dataset.ownerScope}`
    this.preferencesUrl = node.dataset.preferencesUrl
    this.restorePreferences()
  }

  applyPreferences() {
    for (const scope of this.boardTarget.querySelectorAll("[data-dashboard-preferences] [data-market-visualization]")) {
      const range = this.preferences.ranges[scope.dataset.marketVisualization]
      if (range) this.applyRange(scope, range)
    }
  }

  storageFailure(error) {
    return ["SecurityError", "QuotaExceededError"].includes(error.name) ||
      error instanceof SyntaxError || error.message === "Invalid saved UI preferences"
  }

  async restorePreferences() {
    const generation = this.generation
    const abort = new AbortController()
    this.preferencesRestoreAbort = abort
    const timeout = setTimeout(() => abort.abort(), 5000)
    let local = null, warning = ""
    try {
      local = readLocalPreferences(localStorage, this.preferencesKey)
    } catch (error) {
      if (!this.storageFailure(error)) {
        clearTimeout(timeout)
        this.preferencesStatus.textContent = `Browser preference restoration failed: ${error.message}`
        throw error
      }
      warning = "Browser storage unavailable or invalid. "
    }
    if (local) {
      this.preferences = local
      this.applyPreferences()
    }
    try {
      const remote = await this.preferenceRequest("GET", null, abort.signal)
      if (this.disconnected || this.generation !== generation) return
      if (!local && !this.preferencesDirty) {
        this.preferences = remote
        this.applyPreferences()
      }
      this.preferencesStatus.textContent = `${warning}UI preferences restored; prices are freshly fetched, not restored.`
    } catch (error) {
      if (!this.disconnected && this.generation === generation) {
        this.preferencesStatus.textContent = `${warning}Redis preferences unavailable: ${error.message}. UI changes can still be saved locally.`
      }
    } finally {
      clearTimeout(timeout)
      if (!this.disconnected && this.generation === generation) {
        this.preferencesReady = true
        if (this.preferencesDirty) this.savePreferences()
      }
    }
  }

  savePreferences() {
    if (this.disconnected) return
    clearTimeout(this.preferencesTimer)
    this.preferencesWriteAbort?.abort()
    const snapshot = this.preferences
    const generation = this.generation
    let warning = ""
    try {
      localStorage.setItem(this.preferencesKey, JSON.stringify({ savedAt: Date.now(), preferences: snapshot }))
    } catch (error) {
      if (!this.storageFailure(error)) throw error
      warning = "Browser persistence unavailable. "
    }
    this.preferencesStatus.textContent = `${warning}${warning ? "UI preferences not yet saved." : "UI preferences saved in this browser."} Redis synchronization pending.`
    if (!this.preferencesReady) return
    this.preferencesTimer = setTimeout(async () => {
      const abort = new AbortController()
      this.preferencesWriteAbort = abort
      const timeout = setTimeout(() => abort.abort(), 5000)
      try {
        await this.preferenceRequest("PUT", snapshot, abort.signal)
        if (this.disconnected || generation !== this.generation || snapshot !== this.preferences) return
        this.preferencesStatus.textContent = `${warning}UI preferences saved in Redis${warning ? "" : " and this browser"} for up to24 hours. No market data stored.`
      } catch (error) {
        if (!this.disconnected && generation === this.generation && snapshot === this.preferences) {
          this.preferencesStatus.textContent = `${warning}Redis synchronization unavailable: ${error.message}; ${warning ? "preferences are not saved" : "only the browser copy is saved"}.`
        }
      } finally {
        clearTimeout(timeout)
      }
    }, 300)
  }

  async preferenceRequest(method, state, signal) {
    const headers = { Accept: "application/json" }
    if (method === "PUT") {
      headers["Content-Type"] = "application/json"
      headers["X-CSRF-Token"] = document.querySelector('meta[name="csrf-token"]').content
    }
    const response = await fetch(this.preferencesUrl, {
      method, credentials: "same-origin", cache: "no-store", headers, signal,
      ...(method === "PUT" ? { body: JSON.stringify({ preferences: state }) } : {})
    })
    if (response.redirected) throw new Error("Session expired; sign in again")
    const result = await response.json()
    if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`)
    return validatePreferences(result)
  }

  inspectChart(event) {
    const svg = event.currentTarget
    const points = JSON.parse(svg.dataset.marketPoints)
    let index = Number(svg.dataset.marketIndex || 0)
    if (event.type === "keydown") {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
      event.preventDefault()
      index = event.key === "Home" ? 0 : event.key === "End" ? points.length - 1 : index + (event.key === "ArrowRight" ? 1 : -1)
    } else {
      const bounds = svg.getBoundingClientRect()
      index = Math.round((event.clientX - bounds.left) / bounds.width * (points.length - 1))
    }
    index = Math.max(0, Math.min(points.length - 1, index))
    svg.dataset.marketIndex = String(index)
    const point = points[index]
    const prices = points.map(item => Number(item.close))
    const low = Math.min(...prices), high = Math.max(...prices)
    const marker = svg.querySelector("[data-market-marker]")
    marker.setAttribute("cx", String(index * 700 / (points.length - 1)))
    marker.setAttribute("cy", String(high === low ? 100 : 180 - (Number(point.close) - low) / (high - low) * 160))
    marker.removeAttribute("hidden")
    svg.closest("[data-market-visualization]").querySelector("[data-market-inspection]").textContent =
      `${point.date}: ${new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(point.close)} daily close`
  }
}
