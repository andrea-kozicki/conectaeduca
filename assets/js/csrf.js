(function () {
  'use strict';

  function getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]');

    if (!meta) {
      return null;
    }

    return meta.getAttribute('content');
  }

  window.ConectaEduca = window.ConectaEduca || {};
  window.ConectaEduca.getCsrfToken = getCsrfToken;

  window.ConectaEduca.secureFetch = function (url, options = {}) {
    const token = getCsrfToken();

    const headers = new Headers(options.headers || {});

    if (token) {
      headers.set('X-CSRF-Token', token);
    }

    if (!headers.has('Content-Type') && options.body) {
      headers.set('Content-Type', 'application/json');
    }

    return fetch(url, {
      ...options,
      headers,
      credentials: 'same-origin'
    });
  };
})();