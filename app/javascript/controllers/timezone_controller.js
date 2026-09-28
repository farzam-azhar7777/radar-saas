import { Controller } from "@hotwired/stimulus"

// Fills the timezone from the browser when it is still empty, which is right
// for nearly everyone and saves scrolling a list of four hundred.
export default class extends Controller {
  connect() {
    if (this.element.value) return
    try {
      const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if ([...this.element.options].some((o) => o.value === zone)) this.element.value = zone
    } catch (e) {}
  }
}
