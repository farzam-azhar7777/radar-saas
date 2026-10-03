import { Controller } from "@hotwired/stimulus"

// Long enough for the scheduler to tick after a wake, or for the watchdog to
// replace a hung one (it checks every minute, then allows 90 seconds).
const STALL_GRACE_MS = 5 * 60 * 1000

// Second alert path. The macOS CLI notifier can be silently blocked with no
// prompt; Chrome asks properly and is already a registered notification app.
// Also drives the tab title, which works with no permission at all.
export default class extends Controller {
  static targets = ["button", "ready", "readyRow", "testResult"]
  static values = { url: String, interval: { type: Number, default: 30000 } }

  connect() {
    this.seen = new Set(JSON.parse(localStorage.getItem("radar.seenHot") || "[]"))
    this.seenFailures = new Set(JSON.parse(localStorage.getItem("radar.seenFailures") || "[]"))
    // null until the first poll has recorded what already exists, so turning
    // this on does not announce a day of old proposals at once.
    const written = localStorage.getItem("radar.seenWritten")
    this.seenWritten = written === null ? null : new Set(JSON.parse(written))
    this.readyItems = JSON.parse(localStorage.getItem("radar.readyBanners") || "[]")
    this.renderReady()
    this.baseTitle = document.title
    this.render()
    this.poll()
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async enable() {
    if (!("Notification" in window)) return
    await Notification.requestPermission()
    this.render()
    this.poll()
  }

  // One click to prove alerts reach the screen. Chrome can allow them while
  // macOS silently holds them back, and from inside the page the two look
  // identical, so the only honest test is to send one and ask.
  async test() {
    if (!("Notification" in window)) return this.report("This browser cannot show notifications.", "signal")

    let permission = Notification.permission
    if (permission === "default") permission = await Notification.requestPermission()
    this.render()
    if (permission !== "granted") {
      return this.report("Chrome is blocking alerts for this site. Click the icon left of the address, set Notifications to Allow, then try again.", "signal")
    }

    const n = new Notification("Radar test alert", {
      body: "If you can read this, alerts from Radar reach your screen.",
      tag: "radar-test"
    })
    n.onclick = () => { window.focus(); n.close() }
    this.report("Sent. If no alert appeared, macOS is holding Chrome's notifications back: open System Settings, " +
                "Notifications, Google Chrome, turn on Allow notifications and pick Banners or Alerts. " +
                "Also check that no Focus mode is on. Alerts may be waiting in Notification Center.", "muted")
  }

  report(text, tone) {
    if (!this.hasTestResultTarget) return
    this.testResultTarget.textContent = text
    this.testResultTarget.className = `mt-2 text-[0.8125rem] leading-relaxed ${tone === "signal" ? "text-signal" : "text-muted"}`
    this.testResultTarget.hidden = false
  }

  async poll() {
    let data
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      data = await res.json()
    } catch {
      return
    }

    const fresh = data.hot.filter((job) => !this.seen.has(job.id))

    // First load only records what exists; it does not shout about a backlog.
    if (this.seen.size === 0 && fresh.length > 0) {
      this.remember(data.hot.map((j) => j.id))
    } else if (fresh.length > 0) {
      fresh.forEach((job) => this.announce(job))
      this.remember(fresh.map((j) => j.id))
    }

    this.maybeWritten(data)
    this.maybeDigest(data)
    this.maybeFailures(data)
    this.maybeStalled(data)
    document.title = data.inbox_count > 0 ? `(${data.inbox_count}) ${this.baseTitle}` : this.baseTitle
  }

  // A proposal finished writing, whether Radar wrote it on its own or he
  // pressed Write. The new-job alert said a job exists; this says it is ready.
  maybeWritten(data) {
    const written = data.written || []

    if (this.seenWritten === null) {
      this.seenWritten = new Set(written.map((w) => w.id))
    } else {
      written.filter((w) => !this.seenWritten.has(w.id)).forEach((w) => {
        this.seenWritten.add(w.id)
        this.readyItems = this.readyItems.filter((r) => r.url !== w.url)
        this.readyItems.unshift({ id: w.id, title: w.title, url: w.url, readiness: w.readiness })
        this.announceWritten(w)
      })
    }

    localStorage.setItem("radar.seenWritten", JSON.stringify([...this.seenWritten].slice(-200)))
    this.saveReady()
    this.renderReady()
  }

  announceWritten(item) {
    if (!("Notification" in window) || Notification.permission !== "granted") return

    const n = new Notification(item.version > 1 ? `Proposal ready · v${item.version}` : "Proposal ready", {
      body: `${item.title}\n${item.readiness}`,
      tag: `radar-written-${item.id}`,
      requireInteraction: true
    })
    n.onclick = () => { window.focus(); window.location = item.url }
  }

  // Opening the job counts as seeing it, so the banner does not follow him
  // onto the very page it points at.
  renderReady() {
    if (!this.hasReadyTarget || !this.hasReadyRowTarget) return

    const here = window.location.pathname
    if (this.readyItems.some((r) => r.url === here)) {
      this.readyItems = this.readyItems.filter((r) => r.url !== here)
      this.saveReady()
    }

    this.readyTarget.replaceChildren(...this.readyItems.slice(0, 5).map((item) => {
      const row = this.readyRowTarget.content.firstElementChild.cloneNode(true)
      const link = row.querySelector('[data-field="link"]')
      link.textContent = item.title
      link.href = item.url
      row.querySelector('[data-field="readiness"]').textContent = item.readiness
      row.querySelector('[data-field="dismiss"]').addEventListener("click", () => this.dismissReady(item.url))
      return row
    }))
    this.readyTarget.hidden = this.readyItems.length === 0
  }

  dismissReady(url) {
    this.readyItems = this.readyItems.filter((r) => r.url !== url)
    this.saveReady()
    this.renderReady()
  }

  saveReady() {
    localStorage.setItem("radar.readyBanners", JSON.stringify(this.readyItems.slice(0, 20)))
  }

  // A hot job was announced and then the proposal never arrived. That silence
  // is worse than the failure: it looks exactly like a proposal still being
  // written, so it can go unnoticed for a day.
  maybeFailures(data) {
    const failed = (data.failed || []).filter((job) => !this.seenFailures.has(job.id))
    if (failed.length === 0) return

    this.rememberFailures(failed.map((j) => j.id))
    if (Notification.permission !== "granted") return

    if (data.writer_blocked) {
      const n = new Notification("Radar cannot write proposals", {
        body: "The writer is not logged in. Nothing will be written until you re-authenticate.",
        tag: "radar-writer-blocked",
        requireInteraction: true
      })
      n.onclick = () => { window.focus(); window.location = "/" }
      return
    }

    failed.forEach((job) => {
      const n = new Notification("Proposal failed to write", {
        body: `${job.title}\nNothing was saved. Open it to see why.`,
        tag: `radar-failed-${job.id}`,
        requireInteraction: true
      })
      n.onclick = () => { window.focus(); window.location = job.url }
    })
  }

  // Polling dying is the one failure with no symptom: the inbox simply stops
  // filling, which looks exactly like a quiet morning on Upwork.
  //
  // Waking from sleep always looks stalled for a minute or two, until the
  // scheduler ticks or the watchdog revives it, so only a stall that outlasts
  // the grace is announced. And once per stall: remembered across page loads
  // and tabs, which used to re-announce it on every navigation.
  maybeStalled(data) {
    if (!data.polling_stalled) {
      this.stalledSince = null
      localStorage.removeItem("radar.stallAnnounced")
      return
    }
    this.stalledSince ??= Date.now()
    if (Date.now() - this.stalledSince < STALL_GRACE_MS) return
    if (localStorage.getItem("radar.stallAnnounced")) return

    localStorage.setItem("radar.stallAnnounced", String(Date.now()))
    if (Notification.permission !== "granted") return

    const n = new Notification("Radar has stopped finding jobs", {
      body: "No poll has run for a while. Nothing new is arriving.",
      tag: "radar-stalled",
      requireInteraction: true
    })
    n.onclick = () => { window.focus(); window.location = "/" }
  }

  rememberFailures(ids) {
    ids.forEach((id) => this.seenFailures.add(id))
    localStorage.setItem("radar.seenFailures", JSON.stringify([...this.seenFailures]))
  }

  // Quiet matches never interrupt individually. One summary once enough pile up.
  maybeDigest(data) {
    if (data.waiting < data.digest_size) {
      localStorage.removeItem("radar.digestedAt")
      return
    }
    if (localStorage.getItem("radar.digestedAt")) return
    localStorage.setItem("radar.digestedAt", String(data.waiting))

    if (Notification.permission !== "granted") return
    const n = new Notification(`${data.waiting} jobs waiting`, {
      body: "Worth a look, but none strong enough to interrupt you. No proposals written.",
      tag: "radar-digest"
    })
    n.onclick = () => { window.focus(); window.location = "/" }
  }

  announce(job) {
    if (Notification.permission !== "granted") return

    const n = new Notification(`Strong match · ${job.score}`, {
      body: `${job.title}\n${job.budget} · ${job.search}`,
      tag: `radar-${job.id}`,
      requireInteraction: true
    })
    n.onclick = () => {
      window.focus()
      window.location = job.url
    }
  }

  remember(ids) {
    ids.forEach((id) => this.seen.add(id))
    localStorage.setItem("radar.seenHot", JSON.stringify([...this.seen]))
  }

  render() {
    if (!this.hasButtonTarget) return
    const granted = "Notification" in window && Notification.permission === "granted"
    this.buttonTarget.hidden = granted
  }
}
