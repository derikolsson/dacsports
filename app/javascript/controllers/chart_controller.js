import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// Series colours in a fixed order, so a series keeps its colour whatever else is shown.
const SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]

// A line chart from server-rendered JSON:
//   { labels: ["Sep 1", ...], series: [{ label: "Live", data: [1, 2, ...] }, ...] }
// Axis, grid and legend colours from the page's Bootstrap theme, so they follow light and dark mode.
function themeColors() {
  const style = getComputedStyle(document.documentElement)
  const color = name => style.getPropertyValue(`--bs-${name}`).trim()
  return { text: color("body-color"), muted: color("secondary-color"), grid: color("border-color-translucent"), background: color("body-bg") }
}

export default class extends Controller {
  static values = { config: Object }

  connect() {
    const colors = themeColors()
    const { labels, series } = this.configValue
    const canvas = document.createElement("canvas")
    this.element.replaceChildren(canvas)

    this.chart = new Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: series.map((s, i) => ({
          label: s.label,
          data: s.data,
          borderColor: SERIES_COLORS[i],
          backgroundColor: SERIES_COLORS[i],
          borderWidth: 2,
          pointRadius: 0,
          pointHoverRadius: 5,
          pointHoverBorderWidth: 2,
          pointHoverBorderColor: colors.background,
          cubicInterpolationMode: "monotone"
        }))
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: { position: "top", align: "start", labels: { boxWidth: 12, boxHeight: 2, color: colors.text } },
          tooltip: { usePointStyle: true }
        },
        scales: {
          x: { grid: { display: false }, ticks: { color: colors.muted, maxRotation: 0, autoSkipPadding: 16 } },
          y: { beginAtZero: true, grid: { color: colors.grid }, border: { display: false }, ticks: { color: colors.muted, precision: 0 } }
        }
      }
    })

    this.recolor = this.recolor.bind(this)
    document.addEventListener("theme:change", this.recolor)
  }

  disconnect() {
    document.removeEventListener("theme:change", this.recolor)
    this.chart?.destroy()
  }

  recolor() {
    const { text, muted, grid, background } = themeColors()
    const { options, data } = this.chart
    options.plugins.legend.labels.color = text
    options.scales.x.ticks.color = muted
    options.scales.y.ticks.color = muted
    options.scales.y.grid.color = grid
    data.datasets.forEach(dataset => { dataset.pointHoverBorderColor = background })
    this.chart.update("none")
  }
}
