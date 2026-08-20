<?php
declare(strict_types=1);

require_once __DIR__ . '/../../bootstrap/app.php';

use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\CryptoHybrid;

try {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');

    echo json_encode([
        'ok' => true,
        'envelope_version' => CryptoHybrid::CURRENT_VERSION,
        'algorithm' => 'RSA-OAEP',
        'hash' => 'SHA-256',
        'hybrid_algorithm' => CryptoHybrid::CURRENT_ALGORITHM,
        'public_key_pem' => CryptoHybrid::publicKey(),
    ], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
} catch (Throwable $e) {
    AuditLogger::log('erro_public_key', [
        'message' => $e->getMessage(),
    ]);

    http_response_code(500);

    echo json_encode([
        'ok' => false,
        'message' => 'Chave pública indisponível.',
    ], JSON_UNESCAPED_UNICODE);
}
