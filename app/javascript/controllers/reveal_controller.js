import { Controller } from "@hotwired/stimulus"

// Shows and hides one panel, and says so to assistive tech.
export default class extends Controller {
  static targets = ["panel", "toggle"]

  toggle() {
    const opening = this.panelTarget.hidden
    this.panelTarget.hidden = !opening
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(opening))
    if (opening) this.panelTarget.querySelector("input, textarea, button")?.focus({ preventScroll: true })
    if (opening) this.panelTarget.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }
}
