import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "min", "max"]

  connect() {
    this.update()
  }

  update() {
    const kind = this.kindTarget.value
    this.minTarget.hidden = kind === ""
    this.maxTarget.hidden = kind !== "hourly"
    this.minTarget.placeholder = kind === "fixed" ? "Amount" : "From"
    this.maxTarget.placeholder = "To"
    this.minTarget.setAttribute("aria-label", kind === "fixed" ? "Fixed price" : "Hourly from")
  }
}
