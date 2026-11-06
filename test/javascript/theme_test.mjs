import test from "node:test"
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { runInNewContext } from "node:vm"

const source = await readFile(new URL("../../app/javascript/theme.js", import.meta.url), "utf8")
const key = "finance-tracker-theme"

function classList(initial = []) {
  const classes = new Set(initial)
  return {
    contains: name => classes.has(name),
    toggle(name, enabled) { enabled ? classes.add(name) : classes.delete(name) }
  }
}

function browser({ saved = null, readError, writeError } = {}) {
  const values = new Map(saved === null ? [] : [[key, saved]])
  const storage = {
    getItem(name) { if (readError) throw readError; return values.get(name) ?? null },
    setItem(name, value) { if (writeError) throw writeError; values.set(name, value) }
  }
  const events = new Map()
  const listen = (name, handler) => {
    if (!events.has(name)) events.set(name, [])
    events.get(name).push(handler)
  }
  const select = { value: "light", matches: selector => selector === "[data-theme-selector]" }
  const control = { hidden: true }
  const status = { textContent: "", classList: classList(["sr-only"]) }
  const root = { dataset: {}, classList: classList(["unrelated-class"]) }
  let mounted = false
  const document = {
    documentElement: root, addEventListener: listen,
    querySelectorAll(selector) {
      if (!mounted) return []
      return {
        "[data-theme-selector]": [select],
        "[data-theme-control]": [control],
        "[data-theme-status]": [status]
      }[selector]
    }
  }
  const warnings = []
  runInNewContext(source, {
    document, window: { localStorage: storage, addEventListener: listen },
    console: { warn: (...args) => warnings.push(args) }
  })
  const emit = (name, event = {}) => events.get(name).forEach(handler => handler(event))
  return {
    root, select, control, status, storage, values, warnings, emit,
    mount() { mounted = true; emit("DOMContentLoaded") },
    choose(theme) { select.value = theme; emit("change", { target: select }) }
  }
}

test("light is the default and the theme control is hidden until JavaScript connects", () => {
  const app = browser()
  assert.equal(app.root.dataset.theme, "light")
  assert.equal(app.root.classList.contains("dark"), false)
  assert.equal(app.control.hidden, true)
  app.mount()
  assert.equal(app.control.hidden, false)
  assert.equal(app.select.value, "light")
})

test("saved dark and grey palettes apply before the body is parsed", () => {
  for (const theme of ["dark", "grey"]) {
    const app = browser({ saved: theme })
    assert.equal(app.root.dataset.theme, theme)
    assert.equal(app.root.classList.contains("dark"), true)
    assert.equal(app.root.classList.contains("grey"), theme === "grey")
    assert.equal(app.root.classList.contains("unrelated-class"), true)
    app.mount()
    assert.equal(app.select.value, theme)
  }
})

test("all theme selections persist and survive Turbo navigation", () => {
  const app = browser()
  app.mount()
  for (const theme of ["dark", "grey", "light"]) {
    app.choose(theme)
    assert.equal(app.values.get(key), theme)
    assert.equal(app.root.dataset.theme, theme)
    assert.equal(app.root.classList.contains("dark"), theme !== "light")
    assert.equal(app.root.classList.contains("grey"), theme === "grey")
    app.select.value = "stale"
    app.emit("turbo:load")
    assert.equal(app.select.value, theme)
    assert.equal(app.status.textContent, `${theme[0].toUpperCase() + theme.slice(1)} theme selected.`)
  }
})

test("cross-tab changes, clearing storage and history restoration resync appearance", () => {
  const app = browser({ saved: "dark" })
  app.mount()
  app.emit("storage", { storageArea: app.storage, key, newValue: "grey" })
  assert.equal(app.select.value, "grey")
  app.emit("storage", { storageArea: app.storage, key: "other", newValue: "light" })
  assert.equal(app.select.value, "grey")
  app.emit("storage", { storageArea: {}, key, newValue: "light" })
  assert.equal(app.select.value, "grey")
  app.emit("storage", { storageArea: app.storage, key: null, newValue: null })
  assert.equal(app.select.value, "light")
  app.values.set(key, "grey")
  app.emit("pageshow")
  assert.equal(app.select.value, "grey")
})

test("unknown stored preferences are rejected with a diagnostic", () => {
  const app = browser({ saved: "sepia" })
  app.mount()
  assert.equal(app.select.value, "light")
  assert.equal(app.warnings.length, 1)
})

test("blocked storage retains in-page selection and visibly reports failed persistence", () => {
  for (const name of ["SecurityError", "QuotaExceededError"]) {
    const error = Object.assign(new Error("Storage blocked"), { name })
    const app = browser({ readError: name === "SecurityError" ? error : undefined, writeError: error })
    app.mount()
    app.choose("grey")
    app.emit("turbo:load")
    assert.equal(app.select.value, "grey")
    assert.match(app.status.textContent, /could not save/)
    assert.equal(app.status.classList.contains("sr-only"), false)
    assert.ok(app.warnings.length > 0)
  }
})

test("unexpected storage errors are not silently swallowed", () => {
  assert.throws(() => browser({ readError: new Error("Unexpected failure") }), /Unexpected failure/)
  const app = browser({ writeError: new Error("Unexpected failure") })
  app.mount()
  assert.throws(() => app.choose("dark"), /Unexpected failure/)
})
