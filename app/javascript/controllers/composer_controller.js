import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]

  switch(event) {
    this.bodyTarget.placeholder = event.target.dataset.placeholder
    this.bodyTarget.focus()
  }
}
