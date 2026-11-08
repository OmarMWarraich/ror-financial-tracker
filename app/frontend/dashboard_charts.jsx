import React, { useEffect, useMemo, useReducer, useRef, useState } from "react"
import { createRoot } from "react-dom/client"
import { emptyPreferences, preferenceReducer, ranges, readLocalPreferences } from "./dashboard_state.mjs"

const money = value => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value)

function Chart({ stock, color, range, changeRange, quote }) {
  const [cursor, setCursor] = useState(null)
  const points = useMemo(() => (stock.history?.points || []).slice(-ranges[range]), [stock.history, range])
  const geometry = useMemo(() => {
    const prices = points.map(point => Number(point.close))
    const low = Math.min(...prices), high = Math.max(...prices)
    return points.map((point, index) => ({
      x: index * 700 / (points.length - 1),
      y: high === low ? 100 : 180 - (Number(point.close) - low) / (high - low) * 160
    }))
  }, [points])
  const point = cursor === null ? null : points[Math.min(cursor, points.length - 1)]
  const marker = cursor === null ? null : geometry[Math.min(cursor, points.length - 1)]
  function inspect(event) {
    let index = cursor || 0
    if (event.type === "keydown") {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return
      event.preventDefault()
      index = event.key === "Home" ? 0 : event.key === "End" ? points.length - 1 : index + (event.key === "ArrowRight" ? 1 : -1)
    } else {
      const bounds = event.currentTarget.getBoundingClientRect()
      if (!bounds.width) return
      index = Math.round((event.clientX - bounds.left) / bounds.width * (points.length - 1))
    }
    setCursor(Math.max(0, Math.min(points.length - 1, index)))
  }
  const path = geometry.map(point => `${point.x},${point.y}`).join(" ")
  return <section data-market-visualization={stock.ticker} data-market-color={color} className="min-w-0 rounded-xl border p-4" style={{ borderTop: `3px solid ${color}` }}>
    <h3 className="text-lg font-semibold">{stock.ticker}<span className="block text-sm text-muted-foreground">{stock.name}</span></h3>
    <p className="text-2xl font-semibold" data-market-price={stock.ticker}>{quote ? money(quote.price) : "Unavailable"}</p>
    <p className="text-xs text-muted-foreground" data-market-timing={stock.ticker}>{quote ? `${quote.delayed === true ? "Delayed quote" : "Delay not verified"} / source ${quote.source_at || "Unknown"}` : "Quote unavailable; no current reading"}</p>
    {points.length < 2 ? <p role="status">Daily history unavailable; no simulated chart.</p> : <>
      <div className="flex flex-wrap gap-2 my-3" role="group" aria-label={`${stock.ticker} chart range`}>
        {Object.keys(ranges).map(label => <button key={label} type="button" className="btn btn-sm btn-outline-primary" aria-pressed={range === label} data-market-range={label} onClick={() => { setCursor(null); changeRange(label) }}>{label}</button>)}
      </div>
      <figure data-market-chart={range}>
        <svg viewBox="0 0 700 210" role="img" tabIndex="0" aria-label={`${stock.ticker} daily close. Arrow keys inspect observations.`} onPointerMove={inspect} onKeyDown={inspect} className="w-full" style={{ color }}>
          <polygon points={`0,210 ${path} 700,210`} fill="currentColor" fillOpacity="0.12"/>
          <polyline points={path} fill="none" stroke="currentColor" strokeWidth="3" vectorEffect="non-scaling-stroke"/>
          {marker && <circle data-market-marker r="5" cx={marker.x} cy={marker.y} fill="currentColor"/>}
        </svg>
        <figcaption className="text-xs text-muted-foreground">{points[0].date} - {points.at(-1).date} / USD daily close</figcaption>
      </figure>
      <p data-market-inspection role="status" aria-live="polite" className="mt-2 text-sm">{point ? `${point.date}: ${money(point.close)} daily close` : "Inspect a point for its source session and closing price."}</p>
    </>}
  </section>
}

function DashboardCharts({ node, stocks }) {
  const [preferences, dispatch] = useReducer(preferenceReducer, undefined, emptyPreferences)
  const [quotes, setQuotes] = useState(() => Object.fromEntries(stocks.map(stock => [stock.ticker, stock.quote])))
  const [ready, setReady] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [status, setStatus] = useState("Restoring UI preferences...")
  const edited = useRef(false)
  const key = `dashboard-ui:v1:${node.dataset.ownerScope}`
  const url = node.dataset.preferencesUrl
  useEffect(() => {
    const abort = new AbortController()
    let local = null, storageWarning = ""
    try { local = readLocalPreferences(localStorage, key) } catch { storageWarning = "Browser storage unavailable or invalid. " }
    if (local) dispatch({ type: "restore", value: local })
    async function restore() {
      try {
        const response = await fetch(url, { credentials: "same-origin", cache: "no-store", headers: { Accept: "application/json" }, signal: abort.signal })
        if (response.redirected || !response.ok) throw new Error("Redis preferences unavailable or session expired")
        const remote = await response.json()
        if (!local && !edited.current) dispatch({ type: "restore", value: remote })
        setStatus(`${storageWarning}UI preferences restored; prices are freshly fetched, not restored.`)
      } catch (error) {
        if (!abort.signal.aborted) setStatus(`${storageWarning}${error.message}. UI changes can still be made locally.`)
      } finally {
        if (!abort.signal.aborted) setReady(true)
      }
    }
    restore()
    const updateQuotes = event => setQuotes(current => ({ ...current, ...Object.fromEntries(event.detail.map(stock => [stock.ticker, stock.quote])) }))
    const select = event => { edited.current = true; dispatch({ type: "select", ticker: event.detail }); setDirty(true) }
    node.addEventListener("dashboard:quotes", updateQuotes)
    node.addEventListener("dashboard:selected", select)
    return () => { abort.abort(); node.removeEventListener("dashboard:quotes", updateQuotes); node.removeEventListener("dashboard:selected", select) }
  }, [node, key, url])

  useEffect(() => {
    if (!ready || !dirty) return
    const abort = new AbortController()
    let warning = ""
    try {
      localStorage.setItem(key, JSON.stringify({ savedAt: Date.now(), preferences }))
    } catch { warning = "Browser persistence unavailable. " }
    const timer = setTimeout(async () => {
      try {
        const response = await fetch(url, {
          method: "PUT", credentials: "same-origin", cache: "no-store", signal: abort.signal,
          headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content },
          body: JSON.stringify({ preferences })
        })
        if (response.redirected || !response.ok) throw new Error("Redis synchronization unavailable or session expired")
        setStatus(`${warning}UI preferences saved in Redis${warning ? "" : " and this browser"} for up to24 hours. No market data stored.`)
      } catch (error) {
        if (!abort.signal.aborted) setStatus(`${warning}${error.message}; ${warning ? "preferences are not saved" : "only the browser copy is saved"}.`)
      }
    }, 300)
    return () => { clearTimeout(timer); abort.abort() }
  }, [ready, dirty, preferences, key, url])

  return <>
    <p role="status" data-dashboard-persistence className="mb-3 text-sm text-muted-foreground">{status}</p>
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {stocks.map((stock, index) => <Chart key={stock.ticker} stock={stock} color={["#3b82f6", "#059669", "#d97706", "#8b5cf6", "#f43f5e"][index]} quote={quotes[stock.ticker]} range={preferences.ranges[stock.ticker] || "1M"} changeRange={range => { edited.current = true; dispatch({ type: "range", ticker: stock.ticker, range }); setDirty(true) }}/>)}
    </div>
  </>
}

export function mountCharts(board) {
  const node = board.querySelector("[data-dashboard-react]")
  if (!node) return () => {}
  const root = createRoot(node)
  root.render(<DashboardCharts node={node} stocks={JSON.parse(node.dataset.stocks)}/>)
  return () => root.unmount()
}
