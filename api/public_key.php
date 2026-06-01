<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\CryptoHybrid;

try {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');

    echo json_encode([
        'ok' => true,
        'algorithm' => 'RSA-OAEP',
        'hash' => 'SHA-1',
        'public_key_pem' => CryptoHybrid::publicKey(),
    ], JSON_UNESCAPED_UNICODE);
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