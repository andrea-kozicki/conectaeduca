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

  function sameOriginUrl(input) {
    const url = new URL(String(input), window.location.origin);

    if (url.origin !== window.location.origin) {
      throw new TypeError('secureFetch aceita apenas URLs da mesma origem.');
    }

    return `${url.pathname}${url.search}${url.hash}`;
  }

  window.ConectaEduca.secureFetch = function (url, options = {}) {
    const target = sameOriginUrl(url);
    const token = getCsrfToken();

    const headers = new Headers(options.headers || {});

    if (token) {
      headers.set('X-CSRF-Token', token);
    }

    if (!headers.has('Content-Type') && options.body) {
      headers.set('Content-Type', 'application/json');
    }

    return fetch(target, {
      ...options,
      headers,
      credentials: 'same-origin'
    });
  };
})();