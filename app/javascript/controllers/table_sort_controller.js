import { Controller } from "@hotwired/stimulus"

// Sorts a server-rendered table in place.
//
// Each row carries its sortable values as JSON in data-sort-values. Header links keep
// real ?sort= URLs, so they still work without JavaScript; with it, a click reorders
// the rows and updates the address bar instead of reloading the page.
export default class extends Controller {
  static targets = ["body", "link"]
  static values = { column: String, direction: String, ascendingFirst: Array }

  sort(event) {
    event.preventDefault()
    const column = event.params.column

    if (column === this.columnValue) {
      this.directionValue = this.directionValue === "asc" ? "desc" : "asc"
    } else {
      this.columnValue = column
      // Names and dates read naturally oldest/A first; figures biggest first.
      this.directionValue = this.ascendingFirstValue.includes(column) ? "asc" : "desc"
    }

    this.reorder()
    this.relabel()
    this.remember()
  }

  reorder() {
    const sign = this.directionValue === "asc" ? 1 : -1
    const rows = Array.from(this.bodyTarget.rows).map((row) => [row, JSON.parse(row.dataset.sortValues)[this.columnValue]])

    rows.sort(([, a], [, b]) => {
      if (typeof a === "string" || typeof b === "string") {
        return sign * String(a ?? "").localeCompare(String(b ?? ""), undefined, { sensitivity: "base" })
      }
      return sign * ((a ?? 0) - (b ?? 0))
    })

    this.bodyTarget.append(...rows.map(([row]) => row))
  }

  relabel() {
    const arrow = this.directionValue === "asc" ? " ▲" : " ▼"
    this.linkTargets.forEach((link) => {
      const { tableSortColumnParam: column, tableSortLabelParam: label } = link.dataset
      link.textContent = column === this.columnValue ? label + arrow : label
    })
  }

  // So a reload, bookmark or shared link shows the same order.
  remember() {
    const url = new URL(window.location.href)
    url.searchParams.set("sort", this.columnValue)
    url.searchParams.set("direction", this.directionValue)
    window.history.replaceState(window.history.state, "", url)
  }
}
