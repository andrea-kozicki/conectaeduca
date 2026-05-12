<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

use ConectaEduca\Core\Request;
use ConectaEduca\Core\Response;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\CryptoHybrid;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\RateLimiter;
use ConectaEduca\Service\UsuarioService;

try {
    RateLimiter::requireAllowed('cadastro_usuario', 10, 300);

    $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

    if ($method !== 'POST') {
        Response::json([
            'ok' => false,
            'message' => 'Método não permitido.',
        ], 405);
    }

    $contentType = $_SERVER['CONTENT_TYPE'] ?? '';

    /*
     * Fluxo 1:
     * application/json com envelope criptográfico.
     *
     * Fluxo 2:
     * application/json simples.
     *
     * Fluxo 3:
     * formulário tradicional application/x-www-form-urlencoded.
     *
     * O teste via terminal usa o fluxo 3, então NÃO deve exigir chave privada.
     */
    if (str_contains($contentType, 'application/json')) {
        $payload = Request::json();

        if ($payload === []) {
            Response::json([
                'ok' => false,
                'message' => 'Payload JSON ausente.',
            ], 400);
        }

        if (isset($payload['encrypted_key'], $payload['iv'], $payload['ciphertext'], $payload['tag'])) {
            $dados = CryptoHybrid::decryptEnvelope($payload);
        } else {
            $dados = $payload;
        }

        $csrfToken = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? ($dados['csrf_token'] ?? null);
    } else {
        $dados = $_POST;
        $csrfToken = $_POST['csrf_token'] ?? null;
    }

    Csrf::requireValid(is_string($csrfToken) ? $csrfToken : null);

    $service = new UsuarioService();
    $id = $service->criarLocal($dados);

    AuditLogger::log('usuario_cadastrado', [
        'usuario_id' => $id,
        'email' => $dados['email'] ?? null,
        'origem' => str_contains($contentType, 'application/json') ? 'json' : 'form',
    ]);

    Response::json([
        'ok' => true,
        'message' => 'Usuário cadastrado com sucesso.',
        'id' => $id,
    ]);
} catch (Throwable $e) {
    AuditLogger::log('erro_cadastro_usuario', [
        'message' => $e->getMessage(),
    ]);

    Response::json([
        'ok' => false,
        'message' => $e->getMessage(),
    ], 400);
}