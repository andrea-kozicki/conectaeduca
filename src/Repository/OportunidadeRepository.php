<?php
declare(strict_types=1);

namespace ConectaEduca\Repository;

use PDO;

final class OportunidadeRepository
{
    public function __construct(
        private PDO $pdo
    ) {}

    public function listarPublicas(
            ?string $area = null,
            ?string $busca = null,
            ?string $modalidade = null,
            ?string $tipo = null
        ): array {
            $sql = '
                SELECT o.id,
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
                FROM oportunidades o
                INNER JOIN empresas e ON e.id = o.empresa_id
                WHERE o.status = :status
            ';

            $params = [
                ':status' => 'publicada',
            ];

            if ($area !== null && $area !== '') {
                $sql .= ' AND o.area_conhecimento LIKE :area';
                $params[':area'] = '%' . $area . '%';
            }

            if ($busca !== null && $busca !== '') {
                $sql .= ' AND (
                    o.titulo LIKE :busca
                    OR o.descricao LIKE :busca
                    OR o.requisitos LIKE :busca
                    OR o.area_conhecimento LIKE :busca
                    OR e.nome_fantasia LIKE :busca
                    OR e.razao_social LIKE :busca
                )';

                $params[':busca'] = '%' . $busca . '%';
            }

            if ($modalidade !== null && $modalidade !== '') {
                $sql .= ' AND o.modalidade = :modalidade';
                $params[':modalidade'] = $modalidade;
            }

            if ($tipo !== null && $tipo !== '') {
                $sql .= ' AND o.tipo_oportunidade = :tipo';
                $params[':tipo'] = $tipo;
            }

            $sql .= ' ORDER BY o.data_publicacao DESC, o.id DESC';

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
            'SELECT o.id,
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
        string $areaConhecimento,
        string $status = 'rascunho'
    ): int {
        $dataPublicacao = $status === 'publicada' ? date('Y-m-d H:i:s') : null;

        $stmt = $this->pdo->prepare(
            'INSERT INTO oportunidades
                (empresa_id, titulo, descricao, area_conhecimento, status, data_publicacao, criado_em)
             VALUES
                (:empresa_id, :titulo, :descricao, :area_conhecimento, :status, :data_publicacao, NOW())'
        );

        $stmt->bindValue(':empresa_id', $empresaId, PDO::PARAM_INT);
        $stmt->bindValue(':titulo', $titulo);
        $stmt->bindValue(':descricao', $descricao);
        $stmt->bindValue(':area_conhecimento', $areaConhecimento);
        $stmt->bindValue(':status', $status);
        $stmt->bindValue(':data_publicacao', $dataPublicacao);
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }
}