<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;

final class OportunidadeRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function listarPublicas(?string $area = null, ?string $busca = null): array
    {
        $sql = '
            SELECT o.id, o.empresa_id, o.titulo, o.descricao, o.area, o.status,
                   e.nome AS empresa_nome
            FROM oportunidades o
            INNER JOIN empresas e ON e.id = o.empresa_id
            WHERE o.status = :status
        ';

        $params = [
            ':status' => 'ativa',
        ];

        if ($area !== null && $area !== '') {
            $sql .= ' AND o.area = :area';
            $params[':area'] = $area;
        }

        if ($busca !== null && $busca !== '') {
            $sql .= ' AND (o.titulo LIKE :busca OR o.descricao LIKE :busca)';
            $params[':busca'] = '%' . $busca . '%';
        }

        $sql .= ' ORDER BY o.id DESC';

        $stmt = $this->pdo->prepare($sql);

        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value);
        }

        $stmt->execute();

        return $stmt->fetchAll();
    }

    public function buscarPorId(int $id): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT o.id, o.empresa_id, o.titulo, o.descricao, o.area, o.status,
                    e.nome AS empresa_nome
             FROM oportunidades o
             INNER JOIN empresas e ON e.id = o.empresa_id
             WHERE o.id = :id
             LIMIT 1'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();

        $oportunidade = $stmt->fetch();

        return $oportunidade ?: null;
    }

    public function criar(
        int $empresaId,
        string $titulo,
        string $descricao,
        string $area,
        string $status = 'ativa'
    ): int {
        $stmt = $this->pdo->prepare(
            'INSERT INTO oportunidades (empresa_id, titulo, descricao, area, status, criado_em)
             VALUES (:empresa_id, :titulo, :descricao, :area, :status, NOW())'
        );

        $stmt->bindValue(':empresa_id', $empresaId, PDO::PARAM_INT);
        $stmt->bindValue(':titulo', $titulo);
        $stmt->bindValue(':descricao', $descricao);
        $stmt->bindValue(':area', $area);
        $stmt->bindValue(':status', $status);
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }
}