<?php

declare(strict_types=1);

require '/var/www/conectaeduca/vendor/autoload.php';

use ConectaEduca\Config\Database;

$email = trim((string) getenv('RESET_E2E_EMAIL'));

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "FALHA e-mail de teste inválido\n");
    exit(2);
}

$pdo = Database::connect();

try {
    $pdo->beginTransaction();

    $stmt = $pdo->prepare(
        'SELECT id FROM usuarios WHERE email = :email FOR UPDATE'
    );
    $stmt->execute(['email' => $email]);
    $id = $stmt->fetchColumn();

    $unknownPassword = bin2hex(random_bytes(32));
    $hash = password_hash($unknownPassword, PASSWORD_DEFAULT);

    if ($hash === false) {
        throw new RuntimeException('password_hash falhou');
    }

    if ($id === false) {
        $stmt = $pdo->prepare(
            'INSERT INTO usuarios
             (nome, email, role, senha_hash, conta_ativada, mfa_ativo)
             VALUES
             (:nome, :email, :role, :senha_hash, 1, 0)'
        );
        $stmt->execute([
            'nome' => 'Usuario Reset E2E',
            'email' => $email,
            'role' => 'usuario',
            'senha_hash' => $hash,
        ]);
        $userId = (int) $pdo->lastInsertId();
        $created = true;
    } else {
        $userId = (int) $id;
        $stmt = $pdo->prepare(
            'UPDATE usuarios
             SET nome = :nome,
                 role = :role,
                 senha_hash = :senha_hash,
                 conta_ativada = 1,
                 mfa_ativo = 0
             WHERE id = :id'
        );
        $stmt->execute([
            'nome' => 'Usuario Reset E2E',
            'role' => 'usuario',
            'senha_hash' => $hash,
            'id' => $userId,
        ]);
        $created = false;
    }

    $stmt = $pdo->prepare('DELETE FROM tokens_conta WHERE usuario_id = :id');
    $stmt->execute(['id' => $userId]);

    $stmt = $pdo->prepare('DELETE FROM segredos_mfa WHERE usuario_id = :id');
    $stmt->execute(['id' => $userId]);

    $stmt = $pdo->prepare(
        'DELETE FROM codigos_recuperacao_mfa WHERE usuario_id = :id'
    );
    $stmt->execute(['id' => $userId]);

    $pdo->commit();

    echo "OK usuario_reset_e2e=", $created ? "criado" : "reutilizado", PHP_EOL;
    echo "OK user_id=", $userId, PHP_EOL;
    echo "OK conta_ativada=1 mfa_ativo=0 role=usuario", PHP_EOL;
    echo "INFO senha inicial é aleatória e não foi exibida; use recuperação de senha", PHP_EOL;
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }

    fwrite(STDERR, 'FALHA não foi possível preparar usuário E2E: ' .
        $e::class . PHP_EOL);
    exit(1);
}
