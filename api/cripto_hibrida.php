<?php
declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

use phpseclib3\Crypt\PublicKeyLoader;
use phpseclib3\Crypt\RSA;

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');

function json_error(int $status, string $message): never
{
    http_response_code($status);
    echo json_encode([
        'success' => false,
        'message' => $message,
    ]);
    exit;
}

function descriptografarEntrada(): array
{
    $privateKeyPath = __DIR__ . '/../keys/private.pem';

    if (!is_file($privateKeyPath) || !is_readable($privateKeyPath)) {
    error_log("Chave privada não encontrada ou sem permissão: $privateKeyPath");
    http_response_code(500);
    echo json_encode([
        "success" => false,
        "message" => "Chave privada indisponível no servidor. Execute \"make setup\" na raiz do projeto."
    ]);
    exit;
    }

    $inputJson = file_get_contents('php://input');
    if ($inputJson === false || trim($inputJson) === '') {
        json_error(400, 'Corpo da requisição ausente.');
    }

    if (strlen($inputJson) > 100_000) {
        json_error(413, 'Requisição muito grande.');
    }

    $input = json_decode($inputJson, true);
    if (!is_array($input)) {
        error_log('JSON de entrada inválido.');
        json_error(400, 'Entrada JSON malformada.');
    }

    $encryptedKeyB64     = $input['encryptedKey'] ?? null;
    $ivB64               = $input['iv'] ?? null;
    $encryptedMessageB64 = $input['encryptedMessage'] ?? null;

    if (!is_string($encryptedKeyB64) || !is_string($ivB64) || !is_string($encryptedMessageB64)) {
        json_error(400, 'Dados incompletos ou malformados.');
    }

    $encryptedKey     = base64_decode($encryptedKeyB64, true);
    $iv               = base64_decode($ivB64, true);
    $encryptedMessage = base64_decode($encryptedMessageB64, true);

    if ($encryptedKey === false || $iv === false || $encryptedMessage === false) {
        json_error(400, 'Dados incompletos ou malformados.');
    }

    if (strlen($iv) !== 16) {
        json_error(400, 'IV inválido (esperado 16 bytes).');
    }

    try {
        $privateKeyString = file_get_contents($privateKeyPath);
        if ($privateKeyString === false || trim($privateKeyString) === '') {
            throw new RuntimeException('Falha ao ler a chave privada.');
        }

        $privateKey = PublicKeyLoader::loadPrivateKey($privateKeyString);
        if (!$privateKey instanceof \phpseclib3\Crypt\RSA\PrivateKey) {
            json_error(500, 'Chave privada incompatível.');
        }

        $privateKey = $privateKey
            ->withPadding(RSA::ENCRYPTION_OAEP)
            ->withHash('sha256')
            ->withMGFHash('sha256');

        $aesKey = $privateKey->decrypt($encryptedKey);
    } catch (Throwable $e) {
        error_log('Erro ao descriptografar chave AES: ' . $e->getMessage());
        json_error(500, 'Erro ao descriptografar a chave AES.');
    }

    if (!is_string($aesKey) || strlen($aesKey) !== 32) {
        json_error(500, 'Chave AES inválida (esperado 32 bytes).');
    }

    $plaintext = openssl_decrypt($encryptedMessage, 'aes-256-cbc', $aesKey, OPENSSL_RAW_DATA, $iv);
    if ($plaintext === false) {
        json_error(500, 'Erro ao descriptografar a mensagem.');
    }

    $dados = json_decode($plaintext, true);
    if (!is_array($dados)) {
        json_error(400, 'Mensagem descriptografada inválida.');
    }

    return [
        'dados'  => $dados,
        'aesKey' => $aesKey,
        'iv'     => $iv,
    ];
}

function resposta_criptografada(array $dados, string $aesKey, string $iv): never
{
    if (strlen($aesKey) !== 32 || strlen($iv) !== 16) {
        json_error(500, 'Parâmetros criptográficos inválidos para a resposta.');
    }

    $json = json_encode($dados, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        json_error(500, 'Erro ao serializar a resposta.');
    }

    $encrypted = openssl_encrypt($json, 'aes-256-cbc', $aesKey, OPENSSL_RAW_DATA, $iv);
    if ($encrypted === false) {
        json_error(500, 'Erro ao criptografar a resposta.');
    }

    echo json_encode([
        'encryptedMessage' => base64_encode($encrypted),
        'iv'               => base64_encode($iv),
    ], JSON_UNESCAPED_SLASHES);
    exit;
}
