// Passkey sign-in (login page) and registration (account page), using the browser's native WebAuthn JSON helpers.
// Passkey controls start hidden and are only shown when the browser can use them.
const supported = () =>
  window.PublicKeyCredential &&
  typeof PublicKeyCredential.parseCreationOptionsFromJSON === 'function' &&
  typeof PublicKeyCredential.parseRequestOptionsFromJSON === 'function';

async function postJSON(url, body = {}) {
  const response = await fetch(url, {
    method: 'POST',
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content,
    },
    body: JSON.stringify(body),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || 'Something went wrong. Please try again.');
  return data;
}

function showError(container, error) {
  // The user closing the browser prompt isn't worth an error message.
  if (error.name === 'NotAllowedError' || error.name === 'AbortError') return;

  const target = container.querySelector('[data-passkey-error]');
  if (!target) return;
  target.textContent = error.message;
  target.hidden = false;
}

async function signIn(button) {
  const options = await postJSON(button.dataset.optionsUrl);
  const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(options);
  const credential = await navigator.credentials.get({ publicKey });
  const result = await postJSON(button.dataset.url, { credential: JSON.stringify(credential.toJSON()) });
  window.location.assign(result.redirect_to);
}

async function register(form) {
  const options = await postJSON(form.dataset.optionsUrl);
  const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(options);
  const credential = await navigator.credentials.create({ publicKey });
  const result = await postJSON(form.action, { credential: JSON.stringify(credential.toJSON()) });
  window.location.assign(result.redirect_to);
}

function reveal() {
  if (!supported()) return;
  document.querySelectorAll('[data-passkey]').forEach((element) => { element.hidden = false; });
}

let initialized = false;

export function initializePasskeys() {
  reveal();
  if (initialized) return;
  initialized = true;

  document.addEventListener('turbo:load', reveal);

  document.addEventListener('click', async (event) => {
    const button = event.target.closest('[data-passkey-sign-in]');
    if (!button) return;

    event.preventDefault();
    button.disabled = true;
    try {
      await signIn(button);
    } catch (error) {
      showError(button.closest('[data-passkey]'), error);
      button.disabled = false;
    }
  });

  document.addEventListener('submit', async (event) => {
    const form = event.target.closest('form[data-passkey-register]');
    if (!form) return;

    event.preventDefault();
    const submit = form.querySelector('[type="submit"]');
    submit.disabled = true;
    try {
      await register(form);
    } catch (error) {
      showError(form.closest('[data-passkey]'), error);
      submit.disabled = false;
    }
  });
}
