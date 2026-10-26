import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["all", "item", "count", "apply"]

  connect() {
    this.update()
  }

  toggleAll() {
    this.itemTargets.forEach((box) => { box.checked = this.allTarget.checked })
    this.update()
  }

  update() {
    const picked = this.itemTargets.filter((box) => box.checked).length
    this.countTarget.textContent = picked === 0 ? "None selected" : `${picked} selected`
    this.applyTarget.disabled = picked === 0
    if (this.hasAllTarget) {
      this.allTarget.checked = picked > 0 && picked === this.itemTargets.length
      this.allTarget.indeterminate = picked > 0 && picked < this.itemTargets.length
    }
  }
}
