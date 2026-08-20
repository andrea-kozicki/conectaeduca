(() => {
  'use strict';

  const form = document.getElementById('password-reset-form');
  const tokenInput = document.getElementById('reset_token');
  const status = document.getElementById('reset-token-status');

  if (!form || !tokenInput || !status) {
    return;
  }

  const params = new URLSearchParams(window.location.hash.slice(1));
  const token = (params.get('token') || '').trim();

  /* Remove query/fragment da barra antes que o usuário continue o fluxo. */
  history.replaceState(null, document.title, window.location.pathname);

  if (/^[A-Za-z0-9_-]{43}$/.test(token)) {
    tokenInput.value = token;
    form.hidden = false;
    status.hidden = true;

    const passwordInput = document.getElementById('senha');
    if (passwordInput) {
      passwordInput.focus();
    }

    return;
  }

  status.textContent =
    'Link de recuperação inválido ou incompleto. Solicite um novo link.';
})();
