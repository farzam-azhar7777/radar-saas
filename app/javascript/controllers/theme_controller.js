import { Controller } from "@hotwired/stimulus"

// Light, dark, or whatever the system says. Remembered on this browser only.
export default class extends Controller {
  static targets = ["option"]

  connect() {
    this.render()
  }

  choose(event) {
    const value = event.params.value
    try {
      if (value === "system") localStorage.removeItem("radar.theme")
      else localStorage.setItem("radar.theme", value)
    } catch (e) {}
    if (value === "system") delete document.documentElement.dataset.theme
    else document.documentElement.dataset.theme = value
    this.render()
  }

  render() {
    let current = "system"
    try { current = localStorage.getItem("radar.theme") || "system" } catch (e) {}
    this.optionTargets.forEach((el) => el.setAttribute("aria-pressed", String(el.dataset.themeValueParam === current)))
  }
}
