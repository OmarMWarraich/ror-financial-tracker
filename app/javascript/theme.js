// This non-module asset runs before stylesheets so saved themes apply before paint.
(() => {
  const storageKey = "finance-tracker-theme"
  const themes = ["light", "grey", "dark"]

  function storedTheme(value) {
    if (value === null) return "light"
    if (themes.includes(value)) return value
    console.warn("Unknown saved colour theme; using Light.")
    return "light"
  }

  function readTheme(fallback) {
    try {
      return storedTheme(window.localStorage.getItem(storageKey))
    } catch (error) {
      if (error.name !== "SecurityError") throw error
      console.warn("Colour theme storage is unavailable in this browser.", error)
      return fallback
    }
  }

  let theme = readTheme("light")

  function applyTheme() {
    const root = document.documentElement
    root.dataset.theme = theme
    root.classList.toggle("dark", theme !== "light")
    root.classList.toggle("grey", theme === "grey")
    document.querySelectorAll("[data-theme-selector]").forEach(select => { select.value = theme })
    document.querySelectorAll("[data-theme-control]").forEach(control => { control.hidden = false })
  }

  document.addEventListener("change", event => {
    if (!event.target.matches("[data-theme-selector]")) return
    if (!themes.includes(event.target.value)) throw new RangeError("Unsupported colour theme")
    theme = event.target.value
    applyTheme()
    let saved = true
    try {
      window.localStorage.setItem(storageKey, theme)
    } catch (error) {
      if (!["SecurityError", "QuotaExceededError"].includes(error.name)) throw error
      saved = false
      console.warn("Colour theme could not be saved.", error)
    }
    document.querySelectorAll("[data-theme-status]").forEach(status => {
      status.textContent = saved
        ? `${theme[0].toUpperCase() + theme.slice(1)} theme selected.`
        : "Theme changed, but this browser could not save it."
      status.classList.toggle("sr-only", saved)
    })
  })

  window.addEventListener("storage", event => {
    if (event.storageArea !== window.localStorage) return
    if (event.key !== storageKey && event.key !== null) return
    theme = storedTheme(event.newValue)
    applyTheme()
  })
  window.addEventListener("pageshow", () => {
    theme = readTheme(theme)
    applyTheme()
  })
  document.addEventListener("DOMContentLoaded", applyTheme, { once: true })
  document.addEventListener("turbo:load", applyTheme)
  applyTheme()
})()
