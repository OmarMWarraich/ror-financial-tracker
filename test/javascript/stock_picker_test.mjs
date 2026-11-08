import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const source = readFileSync(new URL("../../app/javascript/controllers/stock_picker_controller.js", import.meta.url), "utf8")
const { default: Picker } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")).toString("base64")}`)

function picker() {
  const controller = new Picker()
  controller.inputTarget = { value: "", select() {}, setAttribute(name, value) { this[name] = value }, removeAttribute(name) { delete this[name] } }
  controller.panelTarget = { hidden: true }
  controller.statusTarget = { textContent: "" }
  controller.moreTarget = { hidden: true, disabled: false }
  controller.listTarget = { innerHTML: "", querySelectorAll: () => [],
    insertAdjacentHTML(position, html) { this.innerHTML += html } }
  controller.urlValue = "/dashboard/listings"
  controller.connect()
  return controller
}

test("opening browses all US stocks and keyboard selection dispatches a symbol without loading charts itself", () => {
  const controller = picker()
  const calls = []
  controller.load = (query, offset) => calls.push({ query, offset })
  controller.open()
  assert.deepEqual(calls, [{ query: "", offset: 0 }])
  assert.equal(controller.inputTarget["aria-expanded"], "true")
  const options = ["ALPHA", "ZULU"].map(ticker => ({ id: `stock-option-${ticker}`, dataset: { stockPickerTicker: ticker },
    setAttribute(name, value) { this[name] = value }, scrollIntoView() {} }))
  controller.listTarget.querySelectorAll = () => options
  controller.key({ key: "ArrowUp", preventDefault() {} })
  assert.equal(controller.inputTarget["aria-activedescendant"], "stock-option-ZULU")
  assert.equal(options[1]["aria-selected"], "true")
  let selection
  controller.dispatch = (name, event) => { selection = { name, ...event } }
  controller.key({ key: "Enter", preventDefault() {} })
  assert.deepEqual(selection, { name: "select", detail: { ticker: "ZULU" } })
  assert.equal(controller.inputTarget["aria-expanded"], "false")
})

test("paged searches append real results and a failed search remains an explicit error", async () => {
  const previous = { fetch: globalThis.fetch, location: globalThis.location }
  globalThis.location = { origin: "http://localhost:3000" }
  const calls = []
  globalThis.fetch = async url => {
    calls.push(url.searchParams.get("offset"))
    return { ok: true, json: async () => ({ html: "<li>Original Zulu</li>", next_offset: calls.length === 1 ? 50 : null }) }
  }
  const controller = picker()
  controller.listTarget.querySelectorAll = () => [null]
  try {
    await controller.load("Zulu", 0)
    assert.equal(controller.nextOffset, 50)
    await controller.load("Zulu", 50)
    assert.equal(controller.listTarget.innerHTML, "<li>Original Zulu</li><li>Original Zulu</li>")
    assert.equal(controller.moreTarget.hidden, true)
    assert.deepEqual(calls, ["0", "50"])
    globalThis.fetch = async () => ({ ok: false, json: async () => ({ error: "Provider quota" }) })
    await controller.load("Unavailable", 0)
    assert.match(controller.statusTarget.textContent, /Stock search unavailable: Provider quota/)
    assert.equal(controller.listTarget.innerHTML, "")
  } finally {
    controller.disconnect()
    for (const [name, value] of Object.entries(previous)) value === undefined ? delete globalThis[name] : globalThis[name] = value
  }
})

test("a stale search cannot overwrite a newer query or a reconnected picker", async () => {
  const previous = { fetch: globalThis.fetch, location: globalThis.location }
  globalThis.location = { origin: "http://localhost:3000" }
  const pending = []
  globalThis.fetch = () => new Promise(resolve => pending.push(resolve))
  const response = html => ({ ok: true, json: async () => ({ html, next_offset: null }) })
  const controller = picker()
  try {
    const old = controller.load("Old", 0)
    const newer = controller.load("New", 0)
    pending[1](response("New result"))
    await newer
    pending[0](response("Old result"))
    await old
    assert.equal(controller.listTarget.innerHTML, "New result")
    const interrupted = controller.load("Interrupted", 0)
    controller.disconnect()
    controller.connect()
    pending[2](response("Interrupted result"))
    await interrupted
    assert.equal(controller.listTarget.innerHTML, "")
  } finally {
    controller.disconnect()
    for (const [name, value] of Object.entries(previous)) value === undefined ? delete globalThis[name] : globalThis[name] = value
  }
})

test("Escape restores the selected stock label and cancels a pending search", () => {
  const controller = picker()
  controller.inputTarget.value = "ALPHA / Original Alpha"
  controller.connect()
  controller.inputTarget.value = "Zulu"
  controller.schedule()
  controller.key({ key: "Escape", preventDefault() {} })
  assert.equal(controller.inputTarget.value, "ALPHA / Original Alpha")
  assert.equal(controller.panelTarget.hidden, true)
  assert.equal(controller.currentQuery, null)
  assert.equal(controller.index, -1)
  controller.disconnect()
})
