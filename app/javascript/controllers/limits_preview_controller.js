import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["output"]
  static values = { url: String }

  refresh() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 250)
  }

  async load() {
    const params = new URLSearchParams()
    for (const [name, value] of new FormData(this.element)) {
      if (name.startsWith("limits[")) params.append(name, value)
    }
    const response = await fetch(`${this.urlValue}?${params}`, { headers: { Accept: "text/html" } })
    if (response.ok) this.outputTarget.innerHTML = await response.text()
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
