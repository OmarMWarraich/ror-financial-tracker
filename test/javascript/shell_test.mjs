import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"

async function controller(name) {
  const source = await readFile(new URL(`../../app/javascript/controllers/${name}_controller.js`, import.meta.url), "utf8")
  // Exercise controller methods without requiring a browser-only import-map dependency in Node.
  return (await import(`data:text/javascript;base64,${Buffer.from(source.replace('import { Controller } from "@hotwired/stimulus"', "class Controller {}")).toString("base64")}`)).default
}

const Shell = await controller("shell")
const Disclosure = await controller("disclosure")
const Alert = await controller("alert")

function element() {
  return {
    dataset: {}, attributes: {}, inert: false,
    setAttribute(name, value) { this.attributes[name] = value },
    removeAttribute(name) { delete this.attributes[name] },
    focus() { globalThis.document.activeElement = this },
    getClientRects() { return [1] }
  }
}

function shell(mobile) {
  globalThis.document = { activeElement: null }
  const query = { matches: mobile, addEventListener() {}, removeEventListener() {} }
  globalThis.window = { matchMedia: () => query }
  const instance = new Shell()
  instance.element = element()
  instance.sidebarTarget = element()
  instance.workspaceTarget = element()
  instance.menuButtonTarget = element()
  instance.collapseButtonTarget = element()
  const first = element()
  const last = element()
  const group = { open: false }
  instance.sidebarTarget.querySelector = () => first
  instance.sidebarTarget.querySelectorAll = selector => selector === ".nav-group" ? [group] : [first, last]
  instance.connect()
  return { instance, query, first, last, group }
}

test("desktop collapse keeps navigation accessible and updates control state", () => {
  const { instance, group } = shell(false)
  instance.toggleCollapsed()
  assert.equal(instance.element.dataset.sidebarCollapsed, "true")
  assert.equal(instance.collapseButtonTarget.attributes["aria-expanded"], "false")
  assert.equal(instance.collapseButtonTarget.attributes["aria-label"], "Expand sidebar")
  assert.equal(instance.sidebarTarget.inert, false)
  assert.equal(group.open, true)
  instance.toggleCollapsed()
  assert.equal(instance.collapseButtonTarget.attributes["aria-expanded"], "true")
})

test("mobile navigation traps focus, closes on Escape and restores the opener", () => {
  const { instance, first, last } = shell(true)
  assert.equal(instance.sidebarTarget.inert, true)
  instance.open()
  assert.equal(instance.workspaceTarget.inert, true)
  assert.equal(instance.sidebarTarget.attributes["aria-modal"], "true")
  assert.equal(document.activeElement, first)
  let prevented = false
  instance.trapFocus({ key: "Tab", shiftKey: true, preventDefault() { prevented = true } })
  assert.equal(prevented, true)
  assert.equal(document.activeElement, last)
  instance.trapFocus({ key: "Tab", shiftKey: false, preventDefault() {} })
  assert.equal(document.activeElement, first)
  instance.escape({ preventDefault() {} })
  assert.equal(instance.workspaceTarget.inert, false)
  assert.equal(instance.sidebarTarget.inert, true)
  assert.equal(instance.menuButtonTarget.attributes["aria-expanded"], "false")
  assert.equal(document.activeElement, instance.menuButtonTarget)
})

test("resize, Turbo caching and disconnect clear modal state", () => {
  const { instance, query } = shell(true)
  instance.open()
  query.matches = false
  instance.resize()
  assert.equal(instance.sidebarTarget.inert, false)
  assert.equal(instance.sidebarTarget.attributes["aria-modal"], undefined)
  query.matches = true
  instance.open()
  instance.beforeCache()
  assert.equal(instance.element.dataset.navigationOpen, undefined)
  assert.equal(instance.workspaceTarget.inert, false)
  instance.disconnect()
  assert.equal(instance.element.dataset.shellReady, undefined)
  assert.equal(instance.sidebarTarget.inert, false)
})

test("profile disclosure closes only for outside click or Escape", () => {
  globalThis.document = { activeElement: null }
  const instance = new Disclosure()
  const trigger = element()
  instance.element = { open: true, contains: target => target === trigger, querySelector: () => trigger }
  instance.outside({ target: trigger })
  assert.equal(instance.element.open, true)
  instance.outside({ target: {} })
  assert.equal(instance.element.open, false)
  instance.element.open = true
  instance.escape({ preventDefault() {} })
  assert.equal(instance.element.open, false)
  assert.equal(document.activeElement, trigger)
})

test("dismissing an alert removes only its own notification", () => {
  const instance = new Alert()
  let removed = false
  instance.element = { remove() { removed = true } }
  instance.dismiss()
  assert.equal(removed, true)
})
