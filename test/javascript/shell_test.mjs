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

function alert() {
  const instance = new Alert()
  const classes = new Set()
  instance.element = {
    removed: false,
    classList: {
      add(name) { classes.add(name) },
      remove(name) { classes.delete(name) },
      contains(name) { return classes.has(name) }
    },
    remove() { this.removed = true }
  }
  instance.connect()
  return instance
}

test("alerts stay visible for 3 seconds then animate out before removal", context => {
  context.mock.timers.enable({ apis: ["setTimeout"] })
  const instance = alert()
  context.mock.timers.tick(2999)
  assert.equal(instance.element.classList.contains("toast-dismissing"), false)
  assert.equal(instance.element.removed, false)
  context.mock.timers.tick(1)
  assert.equal(instance.element.classList.contains("toast-dismissing"), true)
  context.mock.timers.tick(199)
  assert.equal(instance.element.removed, false)
  context.mock.timers.tick(1)
  assert.equal(instance.element.removed, true)
})

test("manual dismissal animates only its own toast and repeated clicks do not delay removal", context => {
  context.mock.timers.enable({ apis: ["setTimeout"] })
  const instance = alert()
  const other = alert()
  instance.dismiss()
  assert.equal(instance.element.removed, false)
  context.mock.timers.tick(100)
  instance.dismiss()
  context.mock.timers.tick(100)
  assert.equal(instance.element.removed, true)
  assert.equal(other.element.removed, false)
  assert.equal(other.element.classList.contains("toast-dismissing"), false)
  other.disconnect()
})

test("disconnect clears both auto-dismiss and exit timers and reconnect starts fresh", context => {
  context.mock.timers.enable({ apis: ["setTimeout"] })
  const instance = alert()
  instance.disconnect()
  context.mock.timers.tick(4000)
  assert.equal(instance.element.classList.contains("toast-dismissing"), false)
  instance.connect()
  instance.dismiss()
  instance.disconnect()
  context.mock.timers.tick(4000)
  assert.equal(instance.element.removed, false)
  instance.connect()
  assert.equal(instance.element.classList.contains("toast-dismissing"), false)
  context.mock.timers.tick(3000)
  context.mock.timers.tick(200)
  assert.equal(instance.element.removed, true)
})

test("removing before Turbo caches the page prevents stale toasts on history restoration", context => {
  context.mock.timers.enable({ apis: ["setTimeout"] })
  const instance = alert()
  instance.remove()
  assert.equal(instance.element.removed, true)
  context.mock.timers.tick(4000)
  assert.equal(instance.element.classList.contains("toast-dismissing"), false)
})
