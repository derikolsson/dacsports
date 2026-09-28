import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

Chart.register(...registerables)

// Series colours in a fixed order, so a series keeps its colour whatever else is shown.
const SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]

// A line chart from server-rendered JSON:
//   { labels: ["Sep 1", ...], series: [{ label: "Live", data: [1, 2, ...] }, ...] }
export default class extends Controller {
  static values = { config: Object }

  connect() {
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
          pointHoverBorderColor: "#fff",
          cubicInterpolationMode: "monotone"
        }))
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: { position: "top", align: "start", labels: { boxWidth: 12, boxHeight: 2, color: "#495057" } },
          tooltip: { usePointStyle: true }
        },
        scales: {
          x: { grid: { display: false }, ticks: { color: "#6c757d", maxRotation: 0, autoSkipPadding: 16 } },
          y: { beginAtZero: true, grid: { color: "#e9ecef" }, border: { display: false }, ticks: { color: "#6c757d", precision: 0 } }
        }
      }
    })
  }

  disconnect() {
    this.chart?.destroy()
  }
}
