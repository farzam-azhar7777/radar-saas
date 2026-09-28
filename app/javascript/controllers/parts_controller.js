import { Controller } from "@hotwired/stimulus"

// Opens the rewrite box for one part of a proposal.
//
// Only one box is open at a time. Two open boxes invite typing a note into the
// wrong one, and only the submitted one would have had any effect.
export default class extends Controller {
  static targets = ["panel", "input", "opener"]

  toggle() {
    const opening = this.panelTarget.hidden
    if (opening) this.closeOthers()

    this.panelTarget.hidden = !opening
    if (this.hasOpenerTarget) this.openerTarget.textContent = opening ? "Close" : "Rewrite"
    if (opening && this.hasInputTarget) this.inputTarget.focus()
  }

  closeOthers() {
    this.application.controllers
      .filter((c) => c.identifier === "parts" && c !== this)
      .forEach((c) => c.close())
  }

  close() {
    if (!this.hasPanelTarget || this.panelTarget.hidden) return
    this.panelTarget.hidden = true
    if (this.hasOpenerTarget) this.openerTarget.textContent = "Rewrite"
  }
}
