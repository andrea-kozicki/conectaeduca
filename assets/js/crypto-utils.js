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

let cachedPublicKey = null;

async function getPublicKey() {
  if (cachedPublicKey) {
    return cachedPublicKey;
  }

  const res = await fetch('/api/public_key.php', {
    method: 'GET',
    headers: {
      'Accept': 'application/json'
    },
    credentials: 'same-origin',
    cache: 'no-store'
  });

  if (!res.ok) {
    throw new Error(`Falha ao obter a chave pública: HTTP ${res.status}`);
  }

  const json = await res.json();

  if (!json || typeof json.publicKey !== 'string' || !json.publicKey.trim()) {
    throw new Error('Resposta inválida ao obter a chave pública.');
  }

  const der = base64ToBytes(json.publicKey);

  cachedPublicKey = await window.crypto.subtle.importKey(
    'spki',
    der,
    { name: 'RSA-OAEP', hash: 'SHA-256' },
    true,
    ['encrypt']
  );

  return cachedPublicKey;
}

async function encryptHybrid(message) {
  if (typeof message !== 'string' || message.length === 0) {
    throw new Error('Mensagem inválida para criptografia.');
  }

  const aesKey = await window.crypto.subtle.generateKey(
    { name: 'AES-CBC', length: 256 },
    true,
    ['encrypt', 'decrypt']
  );

  const iv = window.crypto.getRandomValues(new Uint8Array(16));
  const encodedMessage = strToBuffer(message);

  const encryptedMessage = await window.crypto.subtle.encrypt(
    { name: 'AES-CBC', iv },
    aesKey,
    encodedMessage
  );

  const rawAesKey = await window.crypto.subtle.exportKey('raw', aesKey);
  const publicKey = await getPublicKey();

  const encryptedKey = await window.crypto.subtle.encrypt(
    { name: 'RSA-OAEP' },
    publicKey,
    rawAesKey
  );

  return {
    encryptedKey: bufferToBase64(encryptedKey),
    iv: bufferToBase64(iv),
    encryptedMessage: bufferToBase64(encryptedMessage),
    _aesKey: aesKey,
    _iv: iv
  };
}

async function decryptHybrid(payload, aesKey, iv = null) {
  try {
    if (!payload || typeof payload !== 'object') {
      throw new Error('Payload criptografado inválido.');
    }

    if (!payload.encryptedMessage) {
      throw new Error('Mensagem criptografada ausente.');
    }

    const responseIv = payload.iv ? base64ToBytes(payload.iv) : iv;
    const encryptedMsg = base64ToBytes(payload.encryptedMessage);

    if (!responseIv || responseIv.length !== 16) {
      throw new Error('IV da resposta inválido.');
    }

    const decrypted = await window.crypto.subtle.decrypt(
      { name: 'AES-CBC', iv: responseIv },
      aesKey,
      encryptedMsg
    );

    return new TextDecoder().decode(decrypted);
  } catch (error) {
    console.error('Erro ao descriptografar a resposta híbrida:', error);
    return null;
  }
}