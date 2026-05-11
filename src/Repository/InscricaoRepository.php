<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;

final class InscricaoRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function listarPorUsuario(int $usuarioId): array
    {
        $stmt = $this->pdo->prepare(
            'SELECT i.id, i.usuario_id, i.oportunidade_id, i.status, i.criado_em,
                    o.titulo AS oportunidade_titulo,
                    e.nome AS empresa_nome
             FROM inscricoes i
             INNER JOIN oportunidades o ON o.id = i.oportunidade_id
             INNER JOIN empresas e ON e.id = o.empresa_id
             WHERE i.usuario_id = :usuario_id
             ORDER BY i.id DESC'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    public function existe(int $usuarioId, int $oportunidadeId): bool
    {
        $stmt = $this->pdo->prepare(
            'SELECT id
             FROM inscricoes
             WHERE usuario_id = :usuario_id
               AND oportunidade_id = :oportunidade_id
             LIMIT 1'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':oportunidade_id', $oportunidadeId, PDO::PARAM_INT);
        $stmt->execute();

        return (bool) $stmt->fetch();
    }

    public function criar(int $usuarioId, int $oportunidadeId): int
    {
        $stmt = $this->pdo->prepare(
            'INSERT INTO inscricoes (usuario_id, oportunidade_id, status, criado_em)
             VALUES (:usuario_id, :oportunidade_id, :status, NOW())'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':oportunidade_id', $oportunidadeId, PDO::PARAM_INT);
        $stmt->bindValue(':status', 'enviada');
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }

    public function atualizarStatus(int $id, string $status): void
    {
        $stmt = $this->pdo->prepare(
            'UPDATE inscricoes
             SET status = :status
             WHERE id = :id'
        );

        $stmt->bindValue(':status', $status);
        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();
    }
}