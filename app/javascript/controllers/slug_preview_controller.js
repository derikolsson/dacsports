import { Controller } from "@hotwired/stimulus"

// Shows the slug a blank field would save as, while the operator fills in the form.
//
// The server builds the slug (Event#suggested_slug), so the preview includes the -2
// suffix for a slug another event holds. A new event shows it as the field's
// placeholder; a saved one, whose field holds its current slug, shows it below as a
// suggestion whenever it differs.
export default class extends Controller {
  static targets = ["input", "suggestion", "suggestedSlug"]
  static values = { url: String, emptyPlaceholder: String }

  refresh(event) {
    if (event.target === this.inputTarget) return this.toggleSuggestion()

    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.fetch(), 250)
  }

  async fetch() {
    const request = (this.request = (this.request || 0) + 1)
    const body = new FormData(this.element)
    // Not the edit form's PATCH override, and no poster upload on every keystroke.
    body.delete("_method")
    body.delete("event[poster]")

    const response = await fetch(this.urlValue, { method: "POST", body, headers: { Accept: "application/json" } })
    if (!response.ok || request !== this.request) return

    const { slug } = await response.json()
    this.inputTarget.placeholder = slug || this.emptyPlaceholderValue
    if (this.hasSuggestedSlugTarget) this.suggestedSlugTarget.textContent = slug
    this.toggleSuggestion()
  }

  toggleSuggestion() {
    if (!this.hasSuggestionTarget) return

    const slug = this.suggestedSlugTarget.textContent
    const value = this.inputTarget.value
    // A cleared field already shows the suggestion as its placeholder.
    this.suggestionTarget.hidden = !slug || !value || slug === value
  }
}
