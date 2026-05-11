<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;

final class UsuarioRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function buscarPorId(int $id): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id, cognito_sub, nome, email, role, criado_em
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
            'SELECT id, cognito_sub, nome, email, role, criado_em
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
            'SELECT id, cognito_sub, nome, email, role, criado_em
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
                 SET nome = :nome, email = :email
                 WHERE cognito_sub = :sub'
            );

            $stmt->bindValue(':nome', $nome);
            $stmt->bindValue(':email', $email);
            $stmt->bindValue(':sub', $sub);
            $stmt->execute();

            return $this->buscarPorCognitoSub($sub) ?? $existente;
        }

        $stmt = $this->pdo->prepare(
            'INSERT INTO usuarios (cognito_sub, nome, email, role, criado_em)
             VALUES (:sub, :nome, :email, :role, NOW())'
        );

        $stmt->bindValue(':sub', $sub);
        $stmt->bindValue(':nome', $nome);
        $stmt->bindValue(':email', $email);
        $stmt->bindValue(':role', $role);
        $stmt->execute();

        return $this->buscarPorId((int) $this->pdo->lastInsertId());
    }

    public function criarLocal(string $nome, string $email, string $role = 'usuario'): int
    {
        $stmt = $this->pdo->prepare(
            'INSERT INTO usuarios (nome, email, role, criado_em)
             VALUES (:nome, :email, :role, NOW())'
        );

        $stmt->bindValue(':nome', $nome);
        $stmt->bindValue(':email', $email);
        $stmt->bindValue(':role', $role);
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }
}