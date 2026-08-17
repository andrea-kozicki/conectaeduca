document.addEventListener('click', function (event) {
  const button = event.target.closest('.js-toggle-details');

  if (!button) {
    return;
  }

  const targetId = button.getAttribute('aria-controls');
  const details = document.getElementById(targetId);

  if (!details) {
    return;
  }

  const isHidden = details.hasAttribute('hidden');

  if (isHidden) {
    details.removeAttribute('hidden');
    button.setAttribute('aria-expanded', 'true');
    button.textContent = 'Ocultar detalhes';
  } else {
    details.setAttribute('hidden', '');
    button.setAttribute('aria-expanded', 'false');
    button.textContent = 'Ver detalhes';
  }
});