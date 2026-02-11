import vegaEmbed from "vega-embed"

const VegaLite = {
  mounted() {
    this.chartId = this.el.getAttribute("data-chart-id")

    // Listen for chart-specific update events
    this.handleEvent(`vega_lite:${this.chartId}:update`, ({ spec }) => {
      this.renderChart(spec)
    })

    // Legacy global event for backward compatibility
    this.handleEvent("vega_lite_spec", ({ spec }) => {
      this.renderChart(spec)
    })

    // Export handler
    this.handleEvent(`vega_lite:${this.chartId}:export_png`, ({ filename }) => {
      this.exportPng(filename || "chart.png")
    })
  },

  updated() {
    // Re-render if the element is updated by LiveView
  },

  renderChart(spec) {
    vegaEmbed(this.el, spec, {
      actions: false,
      renderer: "canvas",
      theme: "quartz",
      tooltip: { theme: "dark" }
    })
      .then((result) => {
        this.view = result.view
      })
      .catch((error) => {
        console.error("VegaLite render error:", error)
      })
  },

  exportPng(filename) {
    if (!this.view) return
    this.view.toImageURL("png").then((url) => {
      const link = document.createElement("a")
      link.href = url
      link.download = filename
      link.click()
    }).catch((error) => {
      console.error("Export error:", error)
    })
  },

  destroyed() {
    if (this.view) {
      this.view.finalize()
    }
  }
}

export default VegaLite
