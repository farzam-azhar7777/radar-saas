import { Controller } from "@hotwired/stimulus"

// Remembers which sections a person opened or closed on a page, and puts them
// back after the page reloads. Saving anything reloads the page from the
// server, which knows nothing about what was expanded, so without this a list
// collapses every time something in it is added.
//
// Only sections with an id are remembered, and only for this page, for as
// long as the tab is open.
export default class extends Controller {
  connect() {
    this.onToggle = (event) => this.remember(event.target)
    this.onRender = () => this.restore()
    // toggle does not bubble, so listen in the capture phase.
    document.addEventListener("toggle", this.onToggle, true)
    document.addEventListener("turbo:render", this.onRender)
    document.addEventListener("turbo:morph", this.onRender)
    document.addEventListener("turbo:load", this.onRender)
    this.restore()
  }

  disconnect() {
    document.removeEventListener("toggle", this.onToggle, true)
    document.removeEventListener("turbo:render", this.onRender)
    document.removeEventListener("turbo:morph", this.onRender)
    document.removeEventListener("turbo:load", this.onRender)
  }

  get key() {
    return `radar.disclosures.${window.location.pathname}`
  }

  read() {
    try { return JSON.parse(sessionStorage.getItem(this.key) || "{}") } catch (e) { return {} }
  }

  remember(element) {
    if (!(element instanceof HTMLDetailsElement) || !element.id || this.restoring) return
    const state = this.read()
    state[element.id] = element.open
    try { sessionStorage.setItem(this.key, JSON.stringify(state)) } catch (e) {}
  }

  restore() {
    const state = this.read()
    this.restoring = true
    Object.entries(state).forEach(([id, open]) => {
      const element = document.getElementById(id)
      if (element instanceof HTMLDetailsElement && element.open !== open) element.open = open
    })
    // toggle events fire asynchronously; ignore the ones this restore caused.
    setTimeout(() => { this.restoring = false }, 0)
  }
}
