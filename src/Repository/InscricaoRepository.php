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
            'SELECT i.id,
                    i.usuario_id,
                    i.oportunidade_id,
                    i.status,
                    i.observacoes_empresa,
                    i.data_inscricao,
                    i.data_inscricao AS criado_em,
                    i.atualizado_em,
                    o.titulo AS oportunidade_titulo,
                    COALESCE(e.nome_fantasia, e.razao_social) AS empresa_nome
             FROM inscricoes i
             INNER JOIN oportunidades o ON o.id = i.oportunidade_id
             INNER JOIN empresas e ON e.id = o.empresa_id
             WHERE i.usuario_id = :usuario_id
             ORDER BY i.data_inscricao DESC, i.id DESC'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    public function buscarPorIdEUsuario(int $id, int $usuarioId): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT i.id,
                    i.usuario_id,
                    i.oportunidade_id,
                    i.status,
                    i.observacoes_empresa,
                    i.data_inscricao,
                    i.atualizado_em
             FROM inscricoes i
             WHERE i.id = :id
               AND i.usuario_id = :usuario_id
             LIMIT 1'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        $inscricao = $stmt->fetch();

        return $inscricao ?: null;
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
            'INSERT INTO inscricoes
                (usuario_id, oportunidade_id, status, data_inscricao)
             VALUES
                (:usuario_id, :oportunidade_id, :status, NOW())'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':oportunidade_id', $oportunidadeId, PDO::PARAM_INT);
        $stmt->bindValue(':status', 'enviada');
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }

    public function cancelarPorUsuario(int $id, int $usuarioId): bool
    {
        $stmt = $this->pdo->prepare(
            'UPDATE inscricoes
             SET status = :status
             WHERE id = :id
               AND usuario_id = :usuario_id
               AND status IN (:status_enviada, :status_em_analise)'
        );

        $stmt->bindValue(':status', 'cancelada_pelo_usuario');
        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':status_enviada', 'enviada');
        $stmt->bindValue(':status_em_analise', 'em_analise');
        $stmt->execute();

        return $stmt->rowCount() > 0;
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