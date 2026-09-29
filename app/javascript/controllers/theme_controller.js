import { Controller } from "@hotwired/stimulus"

const SYSTEM_DARK = matchMedia("(prefers-color-scheme: dark)")
const CHOICES = ["light", "dark", "auto"]

// Light, dark, or follow the system, as chosen on the account page. Lives on <html> so it
// outlasts Turbo page changes; each new <body> carries the signed-in user's choice.
// Dispatches "theme:change" on document when the page switches between light and dark.
export default class extends Controller {
  static targets = ["preference"]

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

  preferenceTargetConnected() { this.apply() }

  apply() {
    const choice = this.choice
    this.render(choice === "auto" ? (SYSTEM_DARK.matches ? "dark" : "light") : choice)
  }

  render(theme) {
    if (this.element.dataset.bsTheme === theme) return
    this.element.dataset.bsTheme = theme
    document.dispatchEvent(new CustomEvent("theme:change", { detail: { theme } }))
  }

  get choice() {
    const preference = this.hasPreferenceTarget ? this.preferenceTarget.dataset.themePreference : "auto"
    return CHOICES.includes(preference) ? preference : "auto"
  }
}
