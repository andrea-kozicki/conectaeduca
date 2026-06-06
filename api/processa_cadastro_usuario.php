<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

use ConectaEduca\Core\Response;
use ConectaEduca\Core\SecureFormRequest;
use ConectaEduca\Security\AuditLogger;
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

    $dados = SecureFormRequest::data();

    if ($dados === []) {
        Response::json([
            'ok' => false,
            'message' => 'Dados ausentes.',
        ], 400);
    }

    Csrf::requireValid(SecureFormRequest::csrfToken($dados));

    $service = new UsuarioService();
    $id = $service->criarLocal($dados);
    $role = (string) ($dados['role'] ?? 'usuario');

    AuditLogger::log('usuario_cadastrado', [
        'usuario_id' => $id,
        'email' => $dados['email'] ?? null,
        'role' => $role,
        'origem' => SecureFormRequest::isEncrypted()
            ? 'formulario_criptografado'
            : 'formulario_tradicional',
    ]);

    Response::json([
        'ok' => true,
        'message' => $role === 'empresa'
            ? 'Conta de empresa cadastrada com sucesso.'
            : 'Usuário cadastrado com sucesso.',
        'id' => $id,
        'redirect' => '/login.php?cadastro=1',
    ]);
} catch (Throwable $e) {
    AuditLogger::log('erro_cadastro_usuario', [
        'message' => $e->getMessage(),
    ]);

    Response::json([
        'ok' => false,
        'message' => 'Não foi possível concluir o cadastro. Verifique os dados informados e tente novamente.',
    ], 400);
}
