import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "input", "results"]
  static values = { url: String }

  connect() {
    this.onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this.dialogTarget.open ? this.dialogTarget.close() : this.open()
      }
    }
    this.onLeave = () => this.dialogTarget.open && this.dialogTarget.close()
    document.addEventListener("keydown", this.onKey)
    document.addEventListener("turbo:before-cache", this.onLeave)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
    document.removeEventListener("turbo:before-cache", this.onLeave)
  }

  open() {
    if (this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.inputTarget.select()
    if (!this.resultsTarget.innerHTML.trim()) this.load()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.dialogTarget.close()
  }

  reset() {
    this.inputTarget.value = ""
    this.resultsTarget.innerHTML = ""
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 150)
  }

  async load() {
    const query = this.inputTarget.value
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)
    const response = await fetch(url, { headers: { Accept: "text/html" } })
    if (query !== this.inputTarget.value) return
    this.resultsTarget.innerHTML = await response.text()
    this.select(0)
  }

  navigate(event) {
    const items = this.items
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.select((this.index + step + items.length) % items.length)
    } else if (event.key === "Enter" && items[this.index]) {
      event.preventDefault()
      items[this.index].click()
    }
  }

  select(index) {
    this.index = index
    this.items.forEach((item, i) => item.setAttribute("aria-selected", i === index))
    this.items[index]?.scrollIntoView({ block: "nearest" })
  }

  get items() {
    return Array.from(this.resultsTarget.querySelectorAll("[data-command-palette-target='item']"))
  }
}
