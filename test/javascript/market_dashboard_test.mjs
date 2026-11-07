import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const source = readFileSync(new URL("../../app/javascript/controllers/market_dashboard_controller.js", import.meta.url), "utf8")
const { default: Dashboard } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")).toString("base64")}`)

test("refresh interval is exactly fifteen minutes and hidden pages consume no requests", () => {
  assert.equal(Dashboard.values.interval.default, 900000)
  const original = globalThis.document
  globalThis.document = { hidden: true, addEventListener() {}, removeEventListener() {} }
  const controller = new Dashboard()
  controller.intervalValue = 900000
  controller.boardTarget = { querySelector: () => null }
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
  controller.range({ currentTarget: buttons[0] })
  assert.equal(charts[0].hidden, false)
  assert.equal(charts[1].hidden, true)
  assert.equal(buttons[0]["aria-pressed"], "true")
  assert.equal(buttons[1]["aria-pressed"], "false")
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
    assert.equal(controller.stopped, undefined)
    assert.equal(controller.boardTarget.innerHTML, "original")
  } finally {
    controller.disconnect()
    globalThis.document = original
  }
})
