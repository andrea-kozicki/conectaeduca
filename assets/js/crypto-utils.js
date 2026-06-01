'use strict';

function strToBuffer(str) {
  return new TextEncoder().encode(str);
}

function bufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunkSize = 0x8000;

  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }

  return btoa(binary);
}

function base64ToBytes(base64) {
  if (typeof base64 !== 'string' || base64.length === 0) {
    throw new Error('Base64 inválido.');
  }

  return Uint8Array.from(atob(base64), c => c.charCodeAt(0));
}

function pemToArrayBuffer(pem) {
  if (typeof pem !== 'string' || !pem.includes('BEGIN PUBLIC KEY')) {
    throw new Error('Chave pública PEM inválida.');
  }

  const base64 = pem
    .replace('-----BEGIN PUBLIC KEY-----', '')
    .replace('-----END PUBLIC KEY-----', '')
    .replace(/\s+/g, '');

  return base64ToBytes(base64).buffer;
}

let cachedPublicKey = null;

async function getPublicKey() {
  if (cachedPublicKey) {
    return cachedPublicKey;
  }

  const response = await fetch('/api/public_key.php', {
    method: 'GET',
    headers: {
      Accept: 'application/json'
    },
    credentials: 'same-origin',
    cache: 'no-store'
  });

  if (!response.ok) {
    throw new Error(`Falha ao obter a chave pública: HTTP ${response.status}`);
  }

  const json = await response.json();

  if (!json || json.ok !== true || typeof json.public_key_pem !== 'string') {
    throw new Error('Resposta inválida ao obter a chave pública.');
  }

  cachedPublicKey = await window.crypto.subtle.importKey(
    'spki',
    pemToArrayBuffer(json.public_key_pem),
    {
      name: 'RSA-OAEP',
      hash: 'SHA-1'
    },
    false,
    ['encrypt']
  );

  return cachedPublicKey;
}

function splitAesGcmCiphertextAndTag(encryptedBuffer) {
  const encrypted = new Uint8Array(encryptedBuffer);

  if (encrypted.length <= 16) {
    throw new Error('Resultado AES-GCM inválido.');
  }

  return {
    ciphertext: encrypted.slice(0, encrypted.length - 16),
    tag: encrypted.slice(encrypted.length - 16)
  };
}

async function encryptHybridEnvelope(data) {
  if (!data || typeof data !== 'object') {
    throw new Error('Dados inválidos para criptografia.');
  }

  const plaintext = JSON.stringify(data);

  if (!plaintext || plaintext === '{}') {
    throw new Error('Payload vazio para criptografia.');
  }

  const aesKey = await window.crypto.subtle.generateKey(
    {
      name: 'AES-GCM',
      length: 256
    },
    true,
    ['encrypt']
  );

  const iv = window.crypto.getRandomValues(new Uint8Array(12));

  const encryptedBuffer = await window.crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv,
      tagLength: 128
    },
    aesKey,
    strToBuffer(plaintext)
  );

  const { ciphertext, tag } = splitAesGcmCiphertextAndTag(encryptedBuffer);

  const rawAesKey = await window.crypto.subtle.exportKey('raw', aesKey);
  const publicKey = await getPublicKey();

  const encryptedKey = await window.crypto.subtle.encrypt(
    {
      name: 'RSA-OAEP'
    },
    publicKey,
    rawAesKey
  );

  return {
    encrypted_key: bufferToBase64(encryptedKey),
    iv: bufferToBase64(iv),
    tag: bufferToBase64(tag),
    ciphertext: bufferToBase64(ciphertext)
  };
}

window.ConectaEduca = window.ConectaEduca || {};
window.ConectaEduca.encryptHybridEnvelope = encryptHybridEnvelope;