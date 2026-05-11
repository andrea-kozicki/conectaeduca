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
            'SELECT id, nome, email, area_atuacao, criado_em
             FROM empresas
             ORDER BY nome'
        );

        return $stmt->fetchAll();
    }

    public function buscarPorId(int $id): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id, nome, email, area_atuacao, criado_em
             FROM empresas
             WHERE id = :id
             LIMIT 1'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();

        $empresa = $stmt->fetch();

        return $empresa ?: null;
    }
}