<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;

final class EmpresaRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function listar(): array
    {
        $stmt = $this->pdo->query(
            'SELECT id,
                    usuario_id,
                    razao_social,
                    nome_fantasia,
                    COALESCE(nome_fantasia, razao_social) AS nome,
                    email,
                    area_atuacao,
                    criado_em
             FROM empresas
             ORDER BY COALESCE(nome_fantasia, razao_social)'
        );

        return $stmt->fetchAll();
    }

    public function buscarPorId(int $id): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id,
                    usuario_id,
                    razao_social,
                    nome_fantasia,
                    COALESCE(nome_fantasia, razao_social) AS nome,
                    email,
                    area_atuacao,
                    criado_em
             FROM empresas
             WHERE id = :id
             LIMIT 1'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();

        $empresa = $stmt->fetch();

        return $empresa ?: null;
    }

    public function buscarPorUsuarioId(int $usuarioId): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id,
                    usuario_id,
                    razao_social,
                    nome_fantasia,
                    COALESCE(nome_fantasia, razao_social) AS nome,
                    email,
                    area_atuacao,
                    criado_em
             FROM empresas
             WHERE usuario_id = :usuario_id
             LIMIT 1'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        $empresa = $stmt->fetch();

        return $empresa ?: null;
    }
}