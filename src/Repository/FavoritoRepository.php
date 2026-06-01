<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;

final class FavoritoRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function listarPorUsuario(int $usuarioId): array
    {
        $stmt = $this->pdo->prepare(
            'SELECT f.id AS favorito_id,
                    f.usuario_id,
                    f.oportunidade_id,
                    f.criado_em AS favoritado_em,
                    o.id,
                    o.empresa_id,
                    o.titulo,
                    o.descricao,
                    o.requisitos,
                    o.area_conhecimento,
                    o.area_conhecimento AS area,
                    o.modalidade,
                    o.tipo_oportunidade,
                    o.cidade,
                    o.estado,
                    o.status,
                    o.data_publicacao,
                    o.data_encerramento,
                    COALESCE(e.nome_fantasia, e.razao_social) AS empresa_nome
             FROM favoritos f
             INNER JOIN oportunidades o ON o.id = f.oportunidade_id
             INNER JOIN empresas e ON e.id = o.empresa_id
             WHERE f.usuario_id = :usuario_id
             ORDER BY f.criado_em DESC, f.id DESC'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
    }

    public function idsFavoritadosPorUsuario(int $usuarioId): array
    {
        $stmt = $this->pdo->prepare(
            'SELECT oportunidade_id
             FROM favoritos
             WHERE usuario_id = :usuario_id'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->execute();

        return array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    }

    public function existe(int $usuarioId, int $oportunidadeId): bool
    {
        $stmt = $this->pdo->prepare(
            'SELECT id
             FROM favoritos
             WHERE usuario_id = :usuario_id
               AND oportunidade_id = :oportunidade_id
             LIMIT 1'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':oportunidade_id', $oportunidadeId, PDO::PARAM_INT);
        $stmt->execute();

        return (bool) $stmt->fetch();
    }

    public function adicionar(int $usuarioId, int $oportunidadeId): void
    {
        $stmt = $this->pdo->prepare(
            'INSERT IGNORE INTO favoritos
                (usuario_id, oportunidade_id, criado_em)
             VALUES
                (:usuario_id, :oportunidade_id, NOW())'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':oportunidade_id', $oportunidadeId, PDO::PARAM_INT);
        $stmt->execute();
    }

    public function remover(int $usuarioId, int $oportunidadeId): bool
    {
        $stmt = $this->pdo->prepare(
            'DELETE FROM favoritos
             WHERE usuario_id = :usuario_id
               AND oportunidade_id = :oportunidade_id'
        );

        $stmt->bindValue(':usuario_id', $usuarioId, PDO::PARAM_INT);
        $stmt->bindValue(':oportunidade_id', $oportunidadeId, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->rowCount() > 0;
    }
}