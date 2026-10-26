import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "count"]
  static values = { storageKey: String }

  connect() {
    this.done = new Set(this.load())
    this.render()
  }

  mark(event) {
    const key = event.detail?.key
    if (!key) return
    this.done.add(key)
    this.save()
    this.render()
  }

  render() {
    let copied = 0
    this.stepTargets.forEach((step) => {
      const on = this.done.has(step.dataset.key)
      if (on) copied += 1
      step.dataset.done = String(on)
      step.querySelector("[data-mark]").textContent = on ? "✓" : step.dataset.number
    })
    if (this.hasCountTarget) {
      const total = this.stepTargets.length
      this.countTarget.textContent = copied === total ? "All copied" : `${copied} of ${total} copied`
    }
  }

  load() {
    try {
      return JSON.parse(sessionStorage.getItem(this.storageKeyValue) || "[]")
    } catch {
      return []
    }
  }

  save() {
    try {
      sessionStorage.setItem(this.storageKeyValue, JSON.stringify([...this.done]))
    } catch {}
  }
}
