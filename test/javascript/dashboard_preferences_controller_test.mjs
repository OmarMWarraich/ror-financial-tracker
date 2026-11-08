import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const helper = readFileSync(new URL("../../app/javascript/dashboard_preferences.js", import.meta.url), "utf8")
const helperModule = `data:text/javascript;base64,${Buffer.from(helper).toString("base64")}`
const source = readFileSync(new URL("../../app/javascript/controllers/market_dashboard_controller.js", import.meta.url), "utf8")
const { default: Dashboard } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}").replace('"dashboard-preferences"', JSON.stringify(helperModule))).toString("base64")}`)

const empty = () => ({ version: 1, ranges: {}, selected: null })

async function withDashboard(check) {
  const previous = { document: globalThis.document, localStorage: globalThis.localStorage, setTimeout, clearTimeout }
  const items = new Map(), timers = new Map()
  let sequence = 0
  globalThis.document = { hidden: true, addEventListener() {}, removeEventListener() {} }
  globalThis.localStorage = { getItem: key => items.get(key), setItem: (key, value) => items.set(key, value), removeItem: key => items.delete(key) }
  globalThis.setTimeout = (callback, delay) => { const id = ++sequence; timers.set(id, { callback, delay }); return id }
  globalThis.clearTimeout = id => timers.delete(id)
  const status = { textContent: "" }
  const charts = ["5D", "1M"].map(range => ({ dataset: { marketChart: range }, hidden: range !== "1M" }))
  const buttons = ["5D", "1M"].map(range => ({ dataset: { marketRange: range }, setAttribute(name, value) { this[name] = value } }))
  const wrapper = { dataset: { ownerScope: "original-owner", preferencesUrl: "/dashboard/preferences" }, querySelector: () => status }
  const scope = { dataset: { marketVisualization: "ALPHA" }, closest: () => wrapper,
    querySelectorAll: selector => selector === "[data-market-chart]" ? charts : buttons }
  const controller = new Dashboard()
  controller.boardTarget = {
    querySelector: selector => selector === "[data-dashboard-preferences]" ? wrapper : null,
    querySelectorAll: selector => selector.includes("[data-market-visualization]") ? [scope] : []
  }
  controller.preferenceRequest = async () => empty()
  try {
    await check({ controller, items, status, charts, scope, timers,
      range: () => controller.range({ currentTarget: { dataset: { marketRange: "5D" }, closest: () => scope } }),
      flush: async () => { for (const [id, timer] of [...timers]) if (timer.delay === 300) { timers.delete(id); await timer.callback() } }
    })
  } finally {
    controller.disconnect()
    for (const [key, value] of Object.entries(previous)) value === undefined ? delete globalThis[key] : globalThis[key] = value
  }
}

test("Stimulus restores owner-local ranges without replacing them with Redis defaults", async () => {
  await withDashboard(async ({ controller, items, charts, status }) => {
    items.set("dashboard-ui:v1:original-owner", JSON.stringify({ savedAt: Date.now(), preferences: { ...empty(), ranges: { ALPHA: "5D" } } }))
    controller.connect()
    await Promise.resolve()
    assert.equal(charts[0].hidden, false)
    assert.equal(charts[1].hidden, true)
    assert.match(status.textContent, /restored/)
  })
})

test("early range edits survive late restore and synchronize metadata only", async () => {
  await withDashboard(async ({ controller, range, items, flush, status }) => {
    let resolveRestore
    const writes = []
    controller.preferenceRequest = (method, state) => method === "GET" ? new Promise(resolve => { resolveRestore = resolve }) :
      Promise.resolve(writes.push(state) && state)
    controller.connect()
    range()
    resolveRestore(empty())
    await Promise.resolve()
    await flush()
    assert.deepEqual(writes[0], { version: 1, ranges: { ALPHA: "5D" }, selected: null })
    assert.deepEqual(JSON.parse(items.get(controller.preferencesKey)).preferences, writes[0])
    assert.match(status.textContent, /saved in Redis and this browser/)
  })
})

test("Redis and browser storage failures are visible without false backup success", async () => {
  await withDashboard(async ({ controller, range, flush, status }) => {
    controller.preferenceRequest = async () => { throw new Error("Redis unavailable") }
    controller.connect()
    await Promise.resolve()
    assert.match(status.textContent, /Redis preferences unavailable/)
    range()
    await flush()
    assert.match(status.textContent, /only the browser copy is saved/)
    globalThis.localStorage.setItem = () => { throw new DOMException("Original disabled storage", "SecurityError") }
    controller.preferenceRequest = async (method, state) => state
    range()
    await flush()
    assert.match(status.textContent, /Browser persistence unavailable/)
  })
})

test("disconnected restores cannot publish into a reconnected Hotwire dashboard", async () => {
  await withDashboard(async ({ controller, charts, status }) => {
    let resolveRestore
    controller.preferenceRequest = () => new Promise(resolve => { resolveRestore = resolve })
    controller.connect()
    const oldRestore = resolveRestore
    controller.disconnect()
    controller.connect()
    oldRestore({ ...empty(), ranges: { ALPHA: "5D" } })
    await Promise.resolve()
    assert.equal(charts[0].hidden, true)
    assert.equal(status.textContent, "")
  })
})
