"use strict";

const fs = require("fs");
const { webcrypto } = require("crypto");

const ENVELOPE_VERSION = 2;
const HYBRID_ALGORITHM = "AES-256-GCM + RSA-OAEP-SHA256";
const OAEP_HASH = "SHA-256";

function pemToArrayBuffer(pem) {
    const base64 = String(pem)
        .replace("-----BEGIN PUBLIC KEY-----", "")
        .replace("-----END PUBLIC KEY-----", "")
        .replace(/\s+/g, "");

    return Uint8Array.from(
        Buffer.from(base64, "base64")
    ).buffer;
}

function toBase64(value) {
    return Buffer
        .from(value)
        .toString("base64");
}

async function main() {
    const raw = fs.readFileSync(0, "utf8");
    const input = JSON.parse(raw);

    if (
        !input
        || typeof input.public_key_pem !== "string"
        || typeof input.plaintext !== "string"
        || input.plaintext.length === 0
    ) {
        throw new Error("Entrada sintética inválida.");
    }

    const publicKey = await webcrypto.subtle.importKey(
        "spki",
        pemToArrayBuffer(input.public_key_pem),
        {
            name: "RSA-OAEP",
            hash: OAEP_HASH,
        },
        false,
        ["encrypt"]
    );

    const aesKey = await webcrypto.subtle.generateKey(
        {
            name: "AES-GCM",
            length: 256,
        },
        true,
        ["encrypt"]
    );

    const iv = webcrypto.getRandomValues(
        new Uint8Array(12)
    );

    const encryptedBuffer =
        await webcrypto.subtle.encrypt(
            {
                name: "AES-GCM",
                iv,
                tagLength: 128,
            },
            aesKey,
            new TextEncoder().encode(input.plaintext)
        );

    const encrypted =
        new Uint8Array(encryptedBuffer);

    if (encrypted.length <= 16) {
        throw new Error(
            "Resultado AES-GCM sintético inválido."
        );
    }

    const ciphertext =
        encrypted.slice(0, -16);
    const tag =
        encrypted.slice(-16);

    const rawAesKey =
        await webcrypto.subtle.exportKey(
            "raw",
            aesKey
        );

    const encryptedKey =
        await webcrypto.subtle.encrypt(
            {
                name: "RSA-OAEP",
            },
            publicKey,
            rawAesKey
        );

    process.stdout.write(
        JSON.stringify({
            version: ENVELOPE_VERSION,
            algorithm: HYBRID_ALGORITHM,
            encrypted_key: toBase64(encryptedKey),
            iv: toBase64(iv),
            tag: toBase64(tag),
            ciphertext: toBase64(ciphertext),
        })
    );
}

main().catch(() => {
    process.stderr.write(
        "Falha ao gerar envelope Web Crypto sintético.\n"
    );
    process.exitCode = 1;
});
