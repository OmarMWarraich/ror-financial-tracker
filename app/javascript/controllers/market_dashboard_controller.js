import { Controller } from "@hotwired/stimulus"
import { mountCharts } from "dashboard-charts"

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
    this.unmountCharts = mountCharts(this.boardTarget)
    this.activate()
  }

  disconnect() {
    this.unmountCharts?.()
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
        this.unmountCharts?.()
        this.boardTarget.innerHTML = result.html
        this.unmountCharts = mountCharts(this.boardTarget)
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
      this.boardTarget.querySelector("[data-dashboard-react]")?.dispatchEvent(new CustomEvent("dashboard:selected", { detail: ticker }))
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
    this.boardTarget.querySelector("[data-dashboard-react]")?.dispatchEvent(new CustomEvent("dashboard:quotes", { detail: stocks }))
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
    for (const chart of scope.querySelectorAll("[data-market-chart]")) chart.hidden = chart.dataset.marketChart !== label
    for (const button of scope.querySelectorAll("[data-market-range]")) button.setAttribute("aria-pressed", String(button.dataset.marketRange === label))
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
