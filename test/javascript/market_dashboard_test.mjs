import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const source = readFileSync(new URL("../../app/javascript/controllers/market_dashboard_controller.js", import.meta.url), "utf8")
const preferencesSource = readFileSync(new URL("../../app/javascript/dashboard_preferences.js", import.meta.url), "utf8")
const preferencesModule = `data:text/javascript;base64,${Buffer.from(preferencesSource).toString("base64")}`
const { default: Dashboard } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}").replace('"dashboard-preferences"', JSON.stringify(preferencesModule))).toString("base64")}`)

test("refresh interval is exactly fifteen minutes and hidden pages consume no requests", () => {
  assert.equal(Dashboard.values.interval.default, 900000)
  const original = globalThis.document
  globalThis.document = { hidden: true, addEventListener() {}, removeEventListener() {} }
  const controller = new Dashboard()
  controller.intervalValue = 900000
  controller.boardTarget = { querySelector: () => null, querySelectorAll: () => [] }
  let refreshes = 0
  controller.refresh = () => { refreshes += 1; controller.lastRefresh = Date.now() }
  try {
    controller.connect()
    assert.equal(refreshes, 0)
    document.hidden = false
    controller.activate()
    assert.equal(refreshes, 1)
    controller.boardTarget.querySelector = () => ({})
    controller.activate()
    assert.equal(refreshes, 1)
    controller.lastRefresh = Date.now() - 900001
    document.hidden = true
    controller.activate()
    assert.equal(refreshes, 1)
    document.hidden = false
    controller.activate()
    assert.equal(refreshes, 2)
    controller.disconnect()
    controller.activate()
    assert.equal(refreshes, 2)
  } finally {
    controller.disconnect()
    globalThis.document = original
  }
})

test("a failed request pauses automatic work and does not erase old figures", async () => {
  const controller = new Dashboard()
  controller.intervalValue = 900000
  controller.boardTarget = { innerHTML: "original", querySelector: () => null, querySelectorAll: () => [] }
  controller.statusTarget = { textContent: "" }
  controller.request = async () => { throw new Error("Provider quota") }
  controller.activate = () => {}
  await controller.refresh()
  assert.equal(controller.stopped, true)
  assert.equal(controller.boardTarget.innerHTML, "original")
  assert.match(controller.statusTarget.textContent, /Previous data is not current/)
})

test("range selection is local and keeps pressed state aligned with visible chart", () => {
  const charts = ["5D", "1Y"].map(label => ({ dataset: { marketChart: label }, hidden: false }))
  const buttons = ["5D", "1Y"].map(label => ({
    dataset: { marketRange: label }, setAttribute(name, value) { this[name] = value }
  }))
  const controller = new Dashboard()
  controller.boardTarget = { querySelectorAll: selector => selector === "[data-market-chart]" ? charts : buttons }
  for (const button of buttons) button.closest = () => controller.boardTarget
  controller.range({ currentTarget: buttons[0] })
  assert.equal(charts[0].hidden, false)
  assert.equal(charts[1].hidden, true)
  assert.equal(buttons[0]["aria-pressed"], "true")
  assert.equal(buttons[1]["aria-pressed"], "false")
})

test("changing one stock range cannot change the other four chart panels", () => {
  const controller = new Dashboard()
  const scopes = Array.from({ length: 5 }, () => {
    const chart = { dataset: { marketChart: "1M" }, hidden: false }
    return { chart, querySelectorAll: selector => selector === "[data-market-chart]" ? [chart] : [] }
  })
  controller.range({ currentTarget: { dataset: { marketRange: "5D" }, closest: () => scopes[0] } })
  assert.equal(scopes[0].chart.hidden, true)
  assert.equal(scopes.filter(scope => !scope.chart.hidden).length, 4)
})

test("keyboard and pointer inspection read real chart points without a provider call", () => {
  const controller = new Dashboard()
  const marker = { setAttribute(name, value) { this[name] = value }, removeAttribute() {} }
  const output = { textContent: "" }
  const svg = {
    dataset: { marketPoints: JSON.stringify([{ date: "2026-11-05", close: 10 }, { date: "2026-11-06", close: 20 }]) },
    querySelector: () => marker, closest: () => ({ querySelector: () => output }),
    getBoundingClientRect: () => ({ left: 0, width: 700 })
  }
  controller.inspectChart({ currentTarget: svg, type: "keydown", key: "End", preventDefault() {} })
  assert.match(output.textContent, /2026-11-06: \$20.00/)
  assert.equal(marker.cx, "700")
  controller.inspectChart({ currentTarget: svg, type: "pointermove", clientX: -5 })
  assert.match(output.textContent, /2026-11-05: \$10.00/)
  assert.equal(marker.cx, "0")
})

test("identical source timestamps are not reported as new provider readings", () => {
  const controller = new Dashboard()
  controller.quoteSources = new Map([["ALPHA", "2026-11-06T19:00:00Z"]])
  controller.boardTarget = { querySelector: () => null, querySelectorAll: () => [] }
  const stock = { ticker: "ALPHA", quote: { source_at: "2026-11-06T19:00:00Z", price: 10 } }
  assert.equal(controller.updateQuotes([stock]), 0)
  stock.quote.source_at = "2026-11-06T19:15:00Z"
  assert.equal(controller.updateQuotes([stock]), 1)
})

test("an interrupted request cannot publish into or stop a reconnected widget", async () => {
  const original = globalThis.document
  globalThis.document = { hidden: true, addEventListener() {}, removeEventListener() {} }
  const controller = new Dashboard()
  controller.intervalValue = 900000
  controller.boardTarget = { innerHTML: "original", querySelector: () => null, querySelectorAll: () => [] }
  controller.statusTarget = { textContent: "" }
  let rejectRequest
  controller.request = () => new Promise((resolve, reject) => { rejectRequest = reject })
  try {
    controller.connect()
    const pending = controller.refresh()
    controller.disconnect()
    controller.connect()
    rejectRequest(new Error("Old interrupted request"))
    await pending
    assert.equal(controller.stopped, false)
    assert.equal(controller.boardTarget.innerHTML, "original")
  } finally {
    controller.disconnect()
    globalThis.document = original
  }
})

test("picker selections load arbitrary stock details and save only the selected symbol", async () => {
  const controller = new Dashboard()
  const detail = { innerHTML: "" }
  controller.boardTarget = { querySelector: () => detail }
  controller.statusTarget = { textContent: "" }
  controller.preferencesKey = "original-owner"
  controller.preferences = { version: 1, ranges: {}, selected: null }
  controller.request = async (mode, ticker) => {
    assert.equal(mode, "detail")
    assert.equal(ticker, "ZULU")
    return { html: "Original Zulu charts and earnings", errors: [], received_at: "2026-11-08T16:00:00Z" }
  }
  let saved
  controller.savePreferences = () => { saved = controller.preferences }
  controller.activate = () => {}
  await controller.pick({ detail: { ticker: "ZULU" } })
  assert.equal(detail.innerHTML, "Original Zulu charts and earnings")
  assert.deepEqual(saved, { version: 1, ranges: {}, selected: "ZULU" })
  assert.match(controller.statusTarget.textContent, /Selected ZULU/)
})
