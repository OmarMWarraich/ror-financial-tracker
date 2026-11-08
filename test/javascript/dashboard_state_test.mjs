import assert from "node:assert/strict"
import { test } from "node:test"
import { readFileSync } from "node:fs"

const source = readFileSync(new URL("../../app/javascript/dashboard_preferences.js", import.meta.url), "utf8")
const { emptyPreferences, updatePreferences: preferenceReducer, readLocalPreferences, retention, validatePreferences } =
  await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

test("independent ranges and selected listing persist UI metadata only", () => {
  let state = preferenceReducer(emptyPreferences(), { type: "range", ticker: "ALPHA", range: "5D" })
  state = preferenceReducer(state, { type: "range", ticker: "BRAVO", range: "6M" })
  state = preferenceReducer(state, { type: "select", ticker: "BRAVO" })
  assert.deepEqual(state, { version: 1, ranges: { ALPHA: "5D", BRAVO: "6M" }, selected: "BRAVO" })
  assert.throws(() => validatePreferences({ ...state, quotes: [123] }), /Invalid/)
  assert.throws(() => preferenceReducer(state, { type: "range", ticker: "ALPHA", range: "__proto__" }), /Invalid/)
  assert.throws(() => validatePreferences({ ...state, selected: "../../credentials" }), /Invalid/)
})

test("browser restoration is owner-key scoped and expires after twenty-four hours", () => {
  const items = new Map()
  const storage = { getItem: key => items.get(key), removeItem: key => items.delete(key) }
  items.set("owner-one", JSON.stringify({ savedAt: 100, preferences: emptyPreferences() }))
  assert.deepEqual(readLocalPreferences(storage, "owner-one", 101), emptyPreferences())
  assert.equal(readLocalPreferences(storage, "owner-two", 101), null)
  assert.equal(readLocalPreferences(storage, "owner-one", 100 + retention), null)
  assert.equal(items.has("owner-one"), false)
  items.set("owner-one", "invalid json")
  assert.throws(() => readLocalPreferences(storage, "owner-one", 101))
  assert.throws(() => readLocalPreferences({ getItem() { throw new Error("Storage disabled") } }, "owner-one"), /disabled/)
})

test("chart state remains bounded to ten ranges", () => {
  let state = emptyPreferences()
  for (let index = 0; index < 20; index++) state = preferenceReducer(state, { type: "range", ticker: `TEST${index}`, range: "1M" })
  assert.equal(Object.keys(state.ranges).length, 10)
})
