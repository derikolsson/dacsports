import { Controller } from "@hotwired/stimulus"

const SYSTEM_DARK = matchMedia("(prefers-color-scheme: dark)")
const ICONS = { light: "bi-sun-fill", dark: "bi-moon-stars-fill", auto: "bi-circle-half" }

// Light, dark, or follow the system, remembered per browser. Lives on <html> so it
// outlasts Turbo page changes; the picker's options may come and go with the body.
// Dispatches "theme:change" on document when the page switches between light and dark.
export default class extends Controller {
  static targets = ["option", "icon"]

  connect() {
    this.apply = this.apply.bind(this)
    this.printLight = () => this.render("light")
    SYSTEM_DARK.addEventListener("change", this.apply)
    window.addEventListener("beforeprint", this.printLight)
    window.addEventListener("afterprint", this.apply)
    this.apply()
  }

  disconnect() {
    SYSTEM_DARK.removeEventListener("change", this.apply)
    window.removeEventListener("beforeprint", this.printLight)
    window.removeEventListener("afterprint", this.apply)
  }

  choose({ params: { choice } }) {
    try { localStorage.setItem("theme", choice) } catch {}
    this.apply()
  }

  optionTargetConnected() { this.markChoice() }
  iconTargetConnected() { this.markChoice() }

  apply() {
    const choice = this.choice
    this.render(choice === "auto" ? (SYSTEM_DARK.matches ? "dark" : "light") : choice)
    this.markChoice()
  }

  render(theme) {
    if (this.element.dataset.bsTheme === theme) return
    this.element.dataset.bsTheme = theme
    document.dispatchEvent(new CustomEvent("theme:change", { detail: { theme } }))
  }

  markChoice() {
    const choice = this.choice
    this.optionTargets.forEach(option => {
      const chosen = option.dataset.themeChoiceParam === choice
      option.classList.toggle("active", chosen)
      option.setAttribute("aria-pressed", chosen)
    })
    this.iconTargets.forEach(icon => {
      icon.classList.remove(...Object.values(ICONS))
      icon.classList.add(ICONS[choice])
    })
  }

  get choice() {
    try {
      const stored = localStorage.getItem("theme")
      return stored in ICONS ? stored : "auto"
    } catch {
      return "auto"
    }
  }
}
