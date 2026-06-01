(function () {
  'use strict';

  function formToObject(form) {
    const data = {};
    const formData = new FormData(form);

    for (const [key, value] of formData.entries()) {
      if (key === 'csrf_token') {
        continue;
      }

      data[key] = value;
    }

    return data;
  }

  function csrfTokenFromForm(form) {
    const input = form.querySelector('input[name="csrf_token"]');

    if (input && input.value) {
      return input.value;
    }

    if (window.ConectaEduca && typeof window.ConectaEduca.getCsrfToken === 'function') {
      return window.ConectaEduca.getCsrfToken();
    }

    return null;
  }

  async function submitEncryptedForm(form) {
    if (
      !window.ConectaEduca ||
      typeof window.ConectaEduca.encryptHybridEnvelope !== 'function'
    ) {
      throw new Error('Utilitário de criptografia híbrida não carregado.');
    }

    const action = form.getAttribute('action') || window.location.href;
    const csrfToken = csrfTokenFromForm(form);
    const data = formToObject(form);
    const envelope = await window.ConectaEduca.encryptHybridEnvelope(data);

    const response = await fetch(action, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/html;q=0.9,*/*;q=0.8',
        ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {})
      },
      credentials: 'same-origin',
      cache: 'no-store',
      body: JSON.stringify(envelope)
    });

    if (response.redirected) {
      window.location.href = response.url;
      return;
    }

    const contentType = response.headers.get('content-type') || '';

    if (contentType.includes('application/json')) {
      const json = await response.json();

      if (json.redirect) {
        window.location.href = json.redirect;
        return;
      }

      if (!response.ok || json.ok === false) {
        throw new Error(json.message || 'Falha ao enviar formulário criptografado.');
      }

      window.location.reload();
      return;
    }

    if (!response.ok) {
      throw new Error(`Falha ao enviar formulário criptografado. HTTP ${response.status}`);
    }

    window.location.reload();
  }

  document.addEventListener('DOMContentLoaded', () => {
    const forms = document.querySelectorAll('form[data-encrypted-form="true"]');

    forms.forEach((form) => {
      form.addEventListener('submit', async (event) => {
        event.preventDefault();

        const submitButton = form.querySelector('button[type="submit"]');
        const originalText = submitButton ? submitButton.textContent : null;

        try {
          if (submitButton) {
            submitButton.disabled = true;
            submitButton.textContent = 'Enviando com criptografia...';
          }

          await submitEncryptedForm(form);
        } catch (error) {
          console.error(error);
          alert(error.message || 'Erro ao enviar formulário criptografado.');
        } finally {
          if (submitButton) {
            submitButton.disabled = false;
            submitButton.textContent = originalText;
          }
        }
      });
    });
  });
})();