import vegaEmbed from "vega-embed"

const VegaLite = {
  mounted() {
    this.chartId = this.el.getAttribute("data-chart-id")
    this._spec = null
    this._resizeTimer = null

    // Listen for chart-specific update events
    this.handleEvent(`vega_lite:${this.chartId}:update`, ({ spec }) => {
      this._spec = spec
      this.renderChart(spec)
    })

    // Legacy global event for backward compatibility
    this.handleEvent("vega_lite_spec", ({ spec }) => {
      this._spec = spec
      this.renderChart(spec)
    })

    // Export handler
    this.handleEvent(`vega_lite:${this.chartId}:export_png`, ({ filename }) => {
      this.exportPng(filename || "chart.png")
    })

    // ResizeObserver for responsive charts
    if (this.el.dataset.responsive === "true") {
      this._resizeObserver = new ResizeObserver(() => {
        if (this._resizeTimer) clearTimeout(this._resizeTimer)
        this._resizeTimer = setTimeout(() => {
          if (this._spec) this.renderChart(this._spec)
        }, 150)
      })
      this._resizeObserver.observe(this.el)
    }
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
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
    }
    if (this._resizeTimer) {
      clearTimeout(this._resizeTimer)
    }
    if (this.view) {
      this.view.finalize()
    }
  }
}

export default VegaLite
