<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;
use RuntimeException;

final class UsuarioRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function buscarPorId(int $id): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id, cognito_sub, nome, email, role, cpf, telefone, data_nascimento,
                    conta_ativada, mfa_ativo, ultimo_login_em, criado_em, atualizado_em
             FROM usuarios
             WHERE id = :id
             LIMIT 1'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();

        $usuario = $stmt->fetch();

        return $usuario ?: null;
    }

    public function buscarPorEmail(string $email): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id, cognito_sub, nome, email, role, cpf, telefone, data_nascimento,
                    conta_ativada, mfa_ativo, ultimo_login_em, criado_em, atualizado_em
             FROM usuarios
             WHERE email = :email
             LIMIT 1'
        );

        $stmt->bindValue(':email', $email);
        $stmt->execute();

        $usuario = $stmt->fetch();

        return $usuario ?: null;
    }

    public function buscarPorCognitoSub(string $sub): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id, cognito_sub, nome, email, role, cpf, telefone, data_nascimento,
                    conta_ativada, mfa_ativo, ultimo_login_em, criado_em, atualizado_em
             FROM usuarios
             WHERE cognito_sub = :sub
             LIMIT 1'
        );

        $stmt->bindValue(':sub', $sub);
        $stmt->execute();

        $usuario = $stmt->fetch();

        return $usuario ?: null;
    }

    public function criarOuAtualizarPorCognito(
        string $sub,
        string $nome,
        string $email,
        string $role = 'usuario'
    ): array {
        $existente = $this->buscarPorCognitoSub($sub);

        if ($existente !== null) {
            $stmt = $this->pdo->prepare(
                'UPDATE usuarios
                 SET nome = :nome,
                     email = :email,
                     ultimo_login_em = NOW()
                 WHERE cognito_sub = :sub'
            );

            $stmt->bindValue(':nome', $nome);
            $stmt->bindValue(':email', $email);

            $stmt->bindValue(':sub', $sub);
            $stmt->execute();

            return $this->buscarPorCognitoSub($sub) ?? $existente;
        }

        $senhaHashInutilizavel = password_hash(bin2hex(random_bytes(32)), PASSWORD_DEFAULT);

        $stmt = $this->pdo->prepare(
            'INSERT INTO usuarios
                (cognito_sub, nome, email, role, senha_hash, conta_ativada, ultimo_login_em, criado_em)
             VALUES
                (:sub, :nome, :email, :role, :senha_hash, 1, NOW(), NOW())'
        );

        $stmt->bindValue(':sub', $sub);
        $stmt->bindValue(':nome', $nome);
        $stmt->bindValue(':email', $email);
        $stmt->bindValue(':role', $role);
        $stmt->bindValue(':senha_hash', $senhaHashInutilizavel);
        $stmt->execute();

        $usuario = $this->buscarPorId((int) $this->pdo->lastInsertId());

        if ($usuario === null) {
            throw new RuntimeException('Usuário criado, mas não encontrado após inserção.');
        }

        return $usuario;
    }

    public function criarLocal(array $dados): int
    {
        $stmt = $this->pdo->prepare(
            'INSERT INTO usuarios
                (nome, email, role, senha_hash, cpf, telefone, data_nascimento, conta_ativada, criado_em)
             VALUES
                (:nome, :email, :role, :senha_hash, :cpf, :telefone, :data_nascimento, 1, NOW())'
        );

        $stmt->bindValue(':nome', $dados['nome']);
        $stmt->bindValue(':email', $dados['email']);
        $stmt->bindValue(':role', $dados['role']);
        $stmt->bindValue(':senha_hash', $dados['senha_hash']);
        $stmt->bindValue(':cpf', $dados['cpf']);
        $stmt->bindValue(':telefone', $dados['telefone']);
        $stmt->bindValue(':data_nascimento', $dados['data_nascimento']);
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }

    public function atualizarPerfil(int $id, array $dados): ?array
    {
        $stmt = $this->pdo->prepare(
            'UPDATE usuarios
             SET nome = :nome,
                 cpf = :cpf,
                 telefone = :telefone,
                 data_nascimento = :data_nascimento
             WHERE id = :id'
        );

        $stmt->bindValue(':nome', $dados['nome']);
        $stmt->bindValue(':cpf', $dados['cpf']);
        $stmt->bindValue(':telefone', $dados['telefone']);
        $stmt->bindValue(':data_nascimento', $dados['data_nascimento']);
        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();

        return $this->buscarPorId($id);
    }
}