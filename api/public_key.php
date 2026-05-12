<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

use ConectaEduca\Security\CryptoHybrid;
use ConectaEduca\Security\AuditLogger;

try {
    header('Content-Type: text/plain; charset=utf-8');
    header('Cache-Control: no-store');

    echo CryptoHybrid::publicKey();
} catch (Throwable $e) {
    AuditLogger::log('erro_public_key', [
        'message' => $e->getMessage(),
    ]);

    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');

    echo json_encode([
        'ok' => false,
        'message' => 'Chave pública indisponível.',
    ], JSON_UNESCAPED_UNICODE);
}