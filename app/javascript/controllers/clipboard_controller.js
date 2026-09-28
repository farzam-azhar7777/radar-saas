import { Controller } from "@hotwired/stimulus"

// Copies exactly the proposal text, nothing else, ready to paste into Upwork.
export default class extends Controller {
  static targets = ["source", "button"]
  static values = { text: String }

  async copy(event) {
    event.preventDefault()
    // An explicit value wins over the visible text. The cover letter is
    // assembled from its parts with the separators Upwork needs, and reading
    // it off the cards would paste the layout instead of the letter.
    const text = this.hasTextValue && this.textValue ? this.textValue : this.sourceTarget.innerText

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const ta = document.createElement("textarea")
      ta.value = text
      document.body.appendChild(ta)
      ta.select()
      document.execCommand("copy")
      ta.remove()
    }

    // Only the label changes, so an icon beside it stays put.
    const button = this.hasButtonTarget ? this.buttonTarget : event.currentTarget
    const label = button.querySelector("span") || button
    const original = label.textContent
    label.textContent = "Copied"
    button.dataset.copied = "true"
    setTimeout(() => {
      label.textContent = original
      delete button.dataset.copied
    }, 1400)
  }
}
