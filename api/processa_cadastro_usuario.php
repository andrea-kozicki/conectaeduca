<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/cripto_hibrida.php';

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

$aesKey = null;
$iv = null;
$pdo = null;

try {
    $entrada = descriptografarEntrada();
    $input   = $entrada['dados'];
    $aesKey  = $entrada['aesKey'];
    $iv      = $entrada['iv'];

    $camposObrigatorios = ['nome', 'email', 'senha', 'telefone', 'cpf', 'data_nascimento'];
    foreach ($camposObrigatorios as $campo) {
        if (!isset($input[$campo]) || trim((string) $input[$campo]) === '') {
            resposta_criptografada([
                'success' => false,
                'message' => "Campo obrigatório ausente: {$campo}",
            ], $aesKey, $iv);
        }
    }

    $nome           = trim((string) $input['nome']);
    $email          = mb_strtolower(trim((string) $input['email']));
    $senha          = (string) $input['senha'];
    $telefone       = trim((string) $input['telefone']);
    $cpf            = preg_replace('/\D+/', '', (string) $input['cpf']);
    $dataNascimento = trim((string) $input['data_nascimento']);

    if (mb_strlen($nome) < 3 || mb_strlen($nome) > 150) {
        resposta_criptografada(['success' => false, 'message' => 'Nome inválido.'], $aesKey, $iv);
    }

    if (!filter_var($email, FILTER_VALIDATE_EMAIL) || mb_strlen($email) > 190) {
        resposta_criptografada(['success' => false, 'message' => 'E-mail inválido.'], $aesKey, $iv);
    }

    if (strlen($senha) < 8 || strlen($senha) > 255) {
        resposta_criptografada(['success' => false, 'message' => 'A senha deve ter entre 8 e 255 caracteres.'], $aesKey, $iv);
    }

    if (!preg_match('/^\d{11}$/', $cpf)) {
        resposta_criptografada(['success' => false, 'message' => 'CPF inválido. Informe 11 dígitos.'], $aesKey, $iv);
    }

    if (mb_strlen($telefone) > 20) {
        resposta_criptografada(['success' => false, 'message' => 'Telefone inválido.'], $aesKey, $iv);
    }

    $dt = DateTime::createFromFormat('Y-m-d', $dataNascimento);
    if (!$dt || $dt->format('Y-m-d') !== $dataNascimento) {
        resposta_criptografada(['success' => false, 'message' => 'Data de nascimento inválida.'], $aesKey, $iv);
    }

    $pdo = getDatabaseConnection();
    $pdo->beginTransaction();

    $stmt = $pdo->prepare('SELECT id FROM usuarios WHERE email = ? LIMIT 1');
    $stmt->execute([$email]);
    if ($stmt->fetch()) {
        $pdo->rollBack();
        resposta_criptografada(['success' => false, 'message' => 'E-mail já cadastrado.'], $aesKey, $iv);
    }

    $stmt = $pdo->prepare('SELECT id FROM usuarios WHERE cpf = ? LIMIT 1');
    $stmt->execute([$cpf]);
    if ($stmt->fetch()) {
        $pdo->rollBack();
        resposta_criptografada(['success' => false, 'message' => 'CPF já cadastrado.'], $aesKey, $iv);
    }

    $senhaHash = password_hash($senha, PASSWORD_DEFAULT);
    if ($senhaHash === false) {
        throw new RuntimeException('Falha ao gerar hash da senha.');
    }

    $stmt = $pdo->prepare(
        'INSERT INTO usuarios (nome, email, senha_hash, cpf, telefone, data_nascimento, conta_ativada, mfa_ativo)
         VALUES (?, ?, ?, ?, ?, ?, 1, 0)'
    );
    $stmt->execute([$nome, $email, $senhaHash, $cpf, $telefone, $dataNascimento]);

    $usuarioId = (int) $pdo->lastInsertId();

    $stmt = $pdo->prepare(
        'INSERT INTO logs_auditoria (tipo_conta, conta_id, acao, recurso, descricao, ip_origem, user_agent, sucesso)
         VALUES (\'usuario\', ?, \'cadastro\', \'usuarios\', ?, ?, ?, 1)'
    );
    $stmt->execute([
        $usuarioId,
        'Cadastro de usuário realizado com sucesso.',
        $_SERVER['REMOTE_ADDR'] ?? null,
        $_SERVER['HTTP_USER_AGENT'] ?? null,
    ]);

    $pdo->commit();

    resposta_criptografada([
        'success'    => true,
        'message'    => 'Cadastro realizado com sucesso.',
        'usuario_id' => $usuarioId,
    ], $aesKey, $iv);
} catch (PDOException $e) {
    if ($pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    error_log('Erro PDO em processa_cadastro_usuario.php: ' . $e->getMessage());

    if ($aesKey !== null && $iv !== null) {
        resposta_criptografada([
            'success' => false,
            'message' => 'Erro no processamento do cadastro.',
        ], $aesKey, $iv);
    }

    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Erro interno no servidor.']);
    exit;
} catch (Throwable $e) {
    if ($pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    error_log('Erro em processa_cadastro_usuario.php: ' . $e->getMessage());

    if ($aesKey !== null && $iv !== null) {
        resposta_criptografada([
            'success' => false,
            'message' => 'Erro no processamento do cadastro.',
        ], $aesKey, $iv);
    }

    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Erro interno no servidor.']);
    exit;
}
