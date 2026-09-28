import { Controller } from "@hotwired/stimulus"

// Refreshes the page while something runs in the background: a scan, a
// write-up, a proposal. Morphing keeps the scroll position.
//
// It holds off whenever the person is doing something here: typing, or with a
// panel or disclosure open. A refresh at that moment would close what they
// opened and throw away what they typed, which is worse than a stale number.
export default class extends Controller {
  static values = { every: { type: Number, default: 3000 } }

  connect() {
    this.dirty = false
    this.onInput = () => { this.dirty = true }
    this.element.addEventListener("input", this.onInput)
    this.timer = setInterval(() => this.refresh(), this.everyValue)
  }

  disconnect() {
    clearInterval(this.timer)
    this.element.removeEventListener("input", this.onInput)
  }

  busy() {
    const active = document.activeElement
    if (active && this.element.contains(active) && ["INPUT", "TEXTAREA", "SELECT"].includes(active.tagName)) return true
    if (this.dirty) return true
    if (this.element.querySelector("details[open] form, [data-reveal-target='panel']:not([hidden])")) return true
    return false
  }

  refresh() {
    if (document.visibilityState !== "visible" || this.busy()) return
    window.Turbo?.visit(window.location.href, { action: "replace" })
  }
}
