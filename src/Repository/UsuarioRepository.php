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
            'SELECT id, nome, email, role, cpf, telefone, data_nascimento,
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
            'SELECT id, nome, email, role, cpf, telefone, data_nascimento,
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

    public function buscarCredenciaisPorEmail(string $email): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT
            id,
            nome,
            email,
            role,
            senha_hash,
            conta_ativada,
            mfa_ativo
         FROM usuarios
         WHERE email = :email
         LIMIT 1'
        );

        $stmt->bindValue(':email', trim($email));
        $stmt->execute();

        $usuario = $stmt->fetch();

        return $usuario ?: null;
    }

    public function registrarUltimoLogin(int $id): void
    {
        $stmt = $this->pdo->prepare(
            'UPDATE usuarios
            SET ultimo_login_em = NOW()
            WHERE id = :id'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();
    }

    public function criarLocal(array $dados): int
    {
        $stmt = $this->pdo->prepare(
            'INSERT INTO usuarios
            (
                nome,
                email,
                role,
                senha_hash,
                cpf,
                telefone,
                data_nascimento,
                conta_ativada,
                criado_em
            )
         VALUES
            (
                :nome,
                :email,
                :role,
                :senha_hash,
                :cpf,
                :telefone,
                :data_nascimento,
                1,
                NOW()
            )'
        );

        $stmt->bindValue(':nome', $dados['nome']);
        $stmt->bindValue(':email', $dados['email']);
        $stmt->bindValue(':role', $dados['role']);
        $stmt->bindValue(':senha_hash', $dados['senha_hash']);
        $stmt->bindValue(':cpf', $dados['cpf']);
        $stmt->bindValue(':telefone', $dados['telefone']);
        $stmt->bindValue(
            ':data_nascimento',
            $dados['data_nascimento']
        );

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
