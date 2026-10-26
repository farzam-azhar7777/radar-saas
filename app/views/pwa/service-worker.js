const HEADERS = { Accept: "application/json", "ngrok-skip-browser-warning": "1" }

self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

self.addEventListener("notificationclick", (event) => {
  const data = event.notification.data || {}
  event.notification.close()

  if (event.action === "write" && data.writeUrl) {
    event.waitUntil(act(data.writeUrl, "Writing the proposal", data))
  } else if (event.action === "dismiss" && data.dismissUrl) {
    event.waitUntil(act(data.dismissUrl, "Dismissed", data))
  } else if (data.url) {
    event.waitUntil(open(data.url))
  }
})

async function act(url, done, data) {
  try {
    const res = await fetch(url, { method: "POST", headers: HEADERS, credentials: "same-origin" })
    const body = await res.json().catch(() => ({}))
    const message = res.ok ? (body.message || done) : "Radar refused this action. Open the job to do it there."
    await self.registration.showNotification(res.ok ? done : "Not done", {
      body: `${data.title}\n${message}`, tag: `radar-done-${data.id}`, data: { url: data.url }
    })
  } catch {
    await self.registration.showNotification("Radar is not reachable", {
      body: data.title, tag: `radar-done-${data.id}`, data: { url: data.url }
    })
  }
}

async function open(url) {
  const target = new URL(url, self.location.origin).href
  const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true })
  const existing = windows.find((w) => w.url === target) || windows[0]
  if (existing) {
    await existing.focus()
    return existing.url === target ? existing : existing.navigate(target)
  }
  return self.clients.openWindow(target)
}
