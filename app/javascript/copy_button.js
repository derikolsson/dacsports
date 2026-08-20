// Copy-to-clipboard for playback IDs and partner snippets on the internal events index.
export function initializeCopyButtons() {
  document.addEventListener('click', async (event) => {
    const button = event.target.closest('.copy-btn');
    if (!button) return;

    event.preventDefault();
    const value = button.dataset.copy;
    if (!value) return;

    try {
      await navigator.clipboard.writeText(value);
    } catch {
      // Clipboard API needs a secure context; fall back so this still works on plain http.
      const scratch = document.createElement('textarea');
      scratch.value = value;
      scratch.setAttribute('readonly', '');
      scratch.style.cssText = 'position:absolute;left:-9999px;';
      document.body.appendChild(scratch);
      scratch.select();
      document.execCommand('copy');
      document.body.removeChild(scratch);
    }

    const original = button.textContent;
    button.textContent = 'copied';
    button.classList.add('copied');
    setTimeout(() => {
      button.textContent = original;
      button.classList.remove('copied');
    }, 1500);
  });
}
