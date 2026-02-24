// Dashboard grid hook: drag-and-drop + resize for widgets on a 12-column grid
const GRID_COLS = 12
const CELL_HEIGHT = 60 // px per grid row unit
const GAP = 16 // px gap between cells

const DashboardGrid = {
  mounted() {
    this.dragging = null
    this.resizing = null
    this.gridRect = null

    this.el.addEventListener("mousedown", (e) => this.onMouseDown(e))
    this._onMouseMove = (e) => this.onMouseMove(e)
    this._onMouseUp = (e) => this.onMouseUp(e)
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
  },

  destroyed() {
    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)
  },

  cellWidth() {
    // Calculate cell width from actual grid container width
    return (this.el.clientWidth - GAP * (GRID_COLS - 1)) / GRID_COLS
  },

  onMouseDown(e) {
    const resizeHandle = e.target.closest("[data-resize]")
    const dragHandle = e.target.closest("[data-drag]")
    if (!resizeHandle && !dragHandle) return

    const widget = e.target.closest("[data-widget-id]")
    if (!widget) return

    e.preventDefault()
    this.gridRect = this.el.getBoundingClientRect()
    const cellW = this.cellWidth()

    const id = widget.dataset.widgetId
    const x = parseInt(widget.dataset.x)
    const y = parseInt(widget.dataset.y)
    const w = parseInt(widget.dataset.w)
    const h = parseInt(widget.dataset.h)

    if (resizeHandle) {
      this.resizing = { id, startMouseX: e.clientX, startMouseY: e.clientY, x, y, w, h, cellW }
      widget.classList.add("opacity-75")
    } else {
      this.dragging = { id, startMouseX: e.clientX, startMouseY: e.clientY, x, y, w, h, cellW, el: widget }
      widget.classList.add("opacity-75", "z-50")
    }
  },

  onMouseMove(e) {
    if (this.dragging) {
      const d = this.dragging
      const dx = e.clientX - d.startMouseX
      const dy = e.clientY - d.startMouseY
      const cellW = d.cellW

      let newX = d.x + Math.round(dx / (cellW + GAP))
      let newY = d.y + Math.round(dy / (CELL_HEIGHT + GAP))
      newX = Math.max(0, Math.min(newX, GRID_COLS - d.w))
      newY = Math.max(0, newY)

      // Live preview via CSS
      d.el.style.gridColumn = `${newX + 1} / span ${d.w}`
      d.el.style.gridRow = `${newY + 1} / span ${d.h}`
      d._newX = newX
      d._newY = newY
    }

    if (this.resizing) {
      const r = this.resizing
      const dx = e.clientX - r.startMouseX
      const dy = e.clientY - r.startMouseY
      const cellW = r.cellW

      let newW = r.w + Math.round(dx / (cellW + GAP))
      let newH = r.h + Math.round(dy / (CELL_HEIGHT + GAP))
      newW = Math.max(2, Math.min(newW, GRID_COLS - r.x))
      newH = Math.max(2, newH)

      const widget = this.el.querySelector(`[data-widget-id="${r.id}"]`)
      if (widget) {
        widget.style.gridColumn = `${r.x + 1} / span ${newW}`
        widget.style.gridRow = `${r.y + 1} / span ${newH}`
      }
      r._newW = newW
      r._newH = newH
    }
  },

  onMouseUp(e) {
    if (this.dragging) {
      const d = this.dragging
      d.el.classList.remove("opacity-75", "z-50")
      d.el.style.gridColumn = ""
      d.el.style.gridRow = ""

      if (d._newX !== undefined && (d._newX !== d.x || d._newY !== d.y)) {
        this.pushEvent("widget_position_changed", {
          id: d.id,
          position: { x: d._newX, y: d._newY, w: d.w, h: d.h }
        })
      }
      this.dragging = null
    }

    if (this.resizing) {
      const r = this.resizing
      const widget = this.el.querySelector(`[data-widget-id="${r.id}"]`)
      if (widget) {
        widget.classList.remove("opacity-75")
        widget.style.gridColumn = ""
        widget.style.gridRow = ""
      }

      if (r._newW !== undefined && (r._newW !== r.w || r._newH !== r.h)) {
        this.pushEvent("widget_position_changed", {
          id: r.id,
          position: { x: r.x, y: r.y, w: r._newW, h: r._newH }
        })
      }
      this.resizing = null
    }
  }
}

export default DashboardGrid
