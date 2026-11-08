export const emptyPreferences = () => ({ version: 1, ranges: {}, selected: null })
export const ranges = { "5D": 5, "1M": 22, "6M": 132, "1Y": 300 }
export const retention = 86400000
const ticker = value => typeof value === "string" && /^[A-Z][A-Z0-9-]{0,19}$/.test(value)

export function validatePreferences(state) {
  if (!state || typeof state !== "object" || Object.keys(state).sort().join(",") !== "ranges,selected,version" ||
      state.version !== 1 || !state.ranges || Array.isArray(state.ranges) || typeof state.ranges !== "object" ||
      Object.keys(state.ranges).length > 10 || !(state.selected === null || ticker(state.selected)) ||
      !Object.entries(state.ranges).every(([symbol, range]) => ticker(symbol) && Object.hasOwn(ranges, range))) {
    throw new Error("Invalid saved UI preferences")
  }
  return state
}

export function preferenceReducer(state, action) {
  if (action.type === "restore") return validatePreferences(action.value)
  if (action.type === "select") return validatePreferences({ ...state, selected: action.ticker })
  if (action.type === "range") {
    const entries = Object.entries(state.ranges).filter(([ticker]) => ticker !== action.ticker).slice(-9)
    return validatePreferences({ ...state, ranges: Object.fromEntries([...entries, [action.ticker, action.range]]) })
  }
  throw new Error("Unknown preference action")
}

export function readLocalPreferences(storage, key, now = Date.now()) {
  const raw = storage.getItem(key)
  if (!raw) return null
  const saved = JSON.parse(raw)
  if (!Number.isFinite(saved.savedAt) || saved.savedAt > now || now - saved.savedAt >= retention) {
    storage.removeItem(key)
    return null
  }
  return validatePreferences(saved.preferences)
}
