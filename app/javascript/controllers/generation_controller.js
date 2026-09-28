import { Controller } from "@hotwired/stimulus"

// A generation takes minutes. Without a clock on screen there is no way to tell
// a running rewrite from a stalled one, so this ticks the elapsed time, paces a
// bar against the median observed run, and says what is happening.
//
// It also polls. The Turbo stream is the primary transport and it is the part
// that fails silently when ActionCable cannot connect, which is exactly the
// case where you would sit and stare at a page that never changes.
export default class extends Controller {
  static targets = ["elapsed", "bar", "note"]
  static values = {
    startedAt: Number,
    typical: { type: Number, default: 160 },
    timeout: { type: Number, default: 900 },
    url: String
  }

  connect() {
    this.tick()
    this.ticker = setInterval(() => this.tick(), 1000)
    this.poller = setInterval(() => this.poll(), 10000)
  }

  disconnect() {
    clearInterval(this.ticker)
    clearInterval(this.poller)
  }

  get seconds() {
    return Math.max(0, Math.round((Date.now() - this.startedAtValue) / 1000))
  }

  tick() {
    const s = this.seconds

    if (this.hasElapsedTarget) this.elapsedTarget.textContent = this.clock(s)

    if (this.hasBarTarget) {
      // Asymptotic, so it never claims to be finished before it is.
      const pct = 100 * (1 - Math.exp(-s / (this.typicalValue / 1.6)))
      this.barTarget.style.width = `${Math.min(96, Math.max(2, pct)).toFixed(1)}%`
    }

    if (this.hasNoteTarget) this.noteTarget.textContent = this.note(s)
  }

  clock(s) {
    if (s < 60) return `${s}s`
    return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`
  }

  note(s) {
    const typical = this.typicalValue
    if (s < 20) return "Reading the post, your projects and the writing rules."
    if (s < typical) return "Drafting, then checking it against the proposal spec."
    if (s < typical * 2.5) return "Longer than usual. A failed check triggers one rewrite, which roughly doubles the time."
    if (s < this.timeoutValue) return "Well past the usual time. It will stop itself at the timeout."
    return "Past the timeout. The next sweep will clear it and give you the button back."
  }

  // Replace the pane only once it is no longer generating. Swapping it while it
  // still is would restart the clock on every poll and wipe anything typed.
  async poll() {
    if (!this.urlValue) return
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html" },
        cache: "no-store",
        credentials: "same-origin"
      })
      if (!response.ok) return

      const fresh = new DOMParser()
        .parseFromString(await response.text(), "text/html")
        .querySelector("#proposal-pane")
      const pane = document.querySelector("#proposal-pane")
      if (!fresh || !pane) return
      if (fresh.querySelector("[data-controller~='generation']")) return

      pane.innerHTML = fresh.innerHTML
    } catch {
      // The stream is the primary path; this is only cover for a dead cable.
    }
  }
}
