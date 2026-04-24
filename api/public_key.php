<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if (!in_array($method, ['GET', 'HEAD'], true)) {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Método não permitido.'
    ]);
    exit;
}

$publicKeyPath = __DIR__ . '/../keys/public.pem';

if (!is_file($publicKeyPath) || !is_readable($publicKeyPath)) {
    error_log('Chave pública indisponível: ' . $publicKeyPath);
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Chave pública indisponível.'
    ]);
    exit;
}

$publicKeyPem = file_get_contents($publicKeyPath);
if ($publicKeyPem === false || trim($publicKeyPem) === '') {
    error_log('Falha ao carregar a chave pública.');
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Falha ao carregar a chave pública.'
    ]);
    exit;
}

$cleaned = preg_replace('/-----BEGIN PUBLIC KEY-----|-----END PUBLIC KEY-----|\R/', '', $publicKeyPem);
if (!is_string($cleaned) || trim($cleaned) === '') {
    error_log('Formato inválido da chave pública.');
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Formato inválido da chave pública.'
    ]);
    exit;
}

echo json_encode([
    'success'   => true,
    'publicKey' => $cleaned,
], JSON_UNESCAPED_SLASHES);
