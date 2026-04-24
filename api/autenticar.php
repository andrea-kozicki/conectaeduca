<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/cripto_hibrida.php';

$https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');

session_set_cookie_params([
    'lifetime' => 0,
    'path'     => '/',
    'domain'   => '',
    'secure'   => $https,
    'httponly' => true,
    'samesite' => 'Lax',
]);

session_start();

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Método não permitido.'
    ]);
    exit;
}

$pdo = null;
$aesKey = null;
$iv = null;

try {
    $entrada = descriptografarEntrada();
    $dados   = $entrada['dados'];
    $aesKey  = $entrada['aesKey'];
    $iv      = $entrada['iv'];

    $email = mb_strtolower(trim((string) ($dados['email'] ?? '')));
    $senha = (string) ($dados['senha'] ?? '');
    $acao  = (string) ($dados['acao'] ?? 'login');

    if ($acao !== 'login') {
        resposta_criptografada([
            'success' => false,
            'message' => 'Ação inválida.'
        ], $aesKey, $iv);
    }

    if (!filter_var($email, FILTER_VALIDATE_EMAIL) || $senha === '') {
        resposta_criptografada([
            'success' => false,
            'message' => 'Credenciais inválidas.'
        ], $aesKey, $iv);
    }

    $pdo = getDatabaseConnection();

    $stmt = $pdo->prepare(
        'SELECT id, email, senha_hash, conta_ativada, mfa_ativo
         FROM usuarios
         WHERE email = ?
         LIMIT 1'
    );
    $stmt->execute([$email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    $credenciaisInvalidas = !$user
        || !isset($user['senha_hash'])
        || !password_verify($senha, (string) $user['senha_hash']);

    if ($credenciaisInvalidas) {
        $stmt = $pdo->prepare(
            'INSERT INTO logs_auditoria (tipo_conta, conta_id, acao, recurso, descricao, ip_origem, user_agent, sucesso)
             VALUES (\'visitante\', NULL, \'login\', \'usuarios\', ?, ?, ?, 0)'
        );
        $stmt->execute([
            'Tentativa de login inválida.',
            $_SERVER['REMOTE_ADDR'] ?? null,
            $_SERVER['HTTP_USER_AGENT'] ?? null,
        ]);

        resposta_criptografada([
            'success' => false,
            'message' => 'Usuário ou senha inválidos.'
        ], $aesKey, $iv);
    }

    if ((int) ($user['conta_ativada'] ?? 0) !== 1) {
        resposta_criptografada([
            'success' => false,
            'message' => 'Conta indisponível para login.'
        ], $aesKey, $iv);
    }

    if ((int) ($user['mfa_ativo'] ?? 0) === 1) {
        resposta_criptografada([
            'success'      => false,
            'mfa_required' => true,
            'message'      => 'MFA habilitado. Implementação pendente nesta versão.'
        ], $aesKey, $iv);
    }

    session_regenerate_id(true);
    $_SESSION['usuario_id'] = (int) $user['id'];
    $_SESSION['usuario_email'] = (string) $user['email'];

    $stmt = $pdo->prepare('UPDATE usuarios SET ultimo_login_em = NOW() WHERE id = ?');
    $stmt->execute([(int) $user['id']]);

    $stmt = $pdo->prepare(
        'INSERT INTO logs_auditoria (tipo_conta, conta_id, acao, recurso, descricao, ip_origem, user_agent, sucesso)
         VALUES (\'usuario\', ?, \'login\', \'usuarios\', ?, ?, ?, 1)'
    );
    $stmt->execute([
        (int) $user['id'],
        'Login realizado com sucesso.',
        $_SERVER['REMOTE_ADDR'] ?? null,
        $_SERVER['HTTP_USER_AGENT'] ?? null,
    ]);

    resposta_criptografada([
        'success'       => true,
        'usuario_id'    => (int) $user['id'],
        'usuario_email' => (string) $user['email'],
        'redirect'      => '/index.php',
        'message'       => 'Login realizado com sucesso.'
    ], $aesKey, $iv);
} catch (Throwable $e) {
    error_log('Erro em autenticar.php: ' . $e->getMessage());

    if ($aesKey !== null && $iv !== null) {
        resposta_criptografada([
            'success' => false,
            'message' => 'Erro no login.'
        ], $aesKey, $iv);
    }

    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Erro interno no servidor.'
    ]);
    exit;
}
