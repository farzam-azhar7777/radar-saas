import { Controller } from "@hotwired/stimulus"

// j / k to move through the inbox, Enter to open. This screen gets used many
// times a day, so it should not need the mouse.
export default class extends Controller {
  static targets = ["item"]
  static classes = ["selected"]

  connect() {
    this.index = -1
    this.handler = this.onKey.bind(this)
    document.addEventListener("keydown", this.handler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handler)
  }

  onKey(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return
    const tag = document.activeElement?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA") return

    if (event.key === "j") this.move(1)
    else if (event.key === "k") this.move(-1)
    else if (event.key === "Enter") this.open()
    else return

    event.preventDefault()
  }

  move(delta) {
    if (this.itemTargets.length === 0) return
    this.index = Math.max(0, Math.min(this.itemTargets.length - 1, this.index + delta))
    this.itemTargets.forEach((el, i) => el.classList.toggle(this.selectedClass, i === this.index))
    this.itemTargets[this.index]?.scrollIntoView({ block: "nearest", behavior: "smooth" })
  }

  open() {
    const current = this.itemTargets[this.index]
    current?.querySelector("a")?.click()
  }
}
