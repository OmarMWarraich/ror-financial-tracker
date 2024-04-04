import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  reload() {
    setTimeout(() => {
        window.location.reload();
    }, 300);
  }
}
