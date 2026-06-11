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
                o.titulo LIKE :busca_titulo
                OR o.descricao LIKE :busca_descricao
                OR o.requisitos LIKE :busca_requisitos
                OR o.area_conhecimento LIKE :busca_area
                OR e.nome_fantasia LIKE :busca_nome_fantasia
                OR e.razao_social LIKE :busca_razao_social
            )';

            $termoBusca = '%' . $busca . '%';

            $params[':busca_titulo'] = $termoBusca;
            $params[':busca_descricao'] = $termoBusca;
            $params[':busca_requisitos'] = $termoBusca;
            $params[':busca_area'] = $termoBusca;
            $params[':busca_nome_fantasia'] = $termoBusca;
            $params[':busca_razao_social'] = $termoBusca;
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

    public function listarGerenciaveisTodas(): array
    {
        $stmt = $this->pdo->query(
            'SELECT o.id,
                    o.empresa_id,
                    o.titulo,
                    o.descricao,
                    o.requisitos,
                    o.area_conhecimento,
                    o.modalidade,
                    o.tipo_oportunidade,
                    o.cidade,
                    o.estado,
                    o.status,
                    o.data_publicacao,
                    o.data_encerramento,
                    o.criado_em,
                    o.atualizado_em,
                    COALESCE(e.nome_fantasia, e.razao_social) AS empresa_nome,
                    COUNT(i.id) AS total_inscricoes
             FROM oportunidades o
             INNER JOIN empresas e ON e.id = o.empresa_id
             LEFT JOIN inscricoes i ON i.oportunidade_id = o.id
             GROUP BY o.id,
                      o.empresa_id,
                      o.titulo,
                      o.descricao,
                      o.requisitos,
                      o.area_conhecimento,
                      o.modalidade,
                      o.tipo_oportunidade,
                      o.cidade,
                      o.estado,
                      o.status,
                      o.data_publicacao,
                      o.data_encerramento,
                      o.criado_em,
                      o.atualizado_em,
                      e.nome_fantasia,
                      e.razao_social
             ORDER BY o.atualizado_em DESC, o.id DESC'
        );

        return $stmt->fetchAll();
    }

    public function listarGerenciaveisPorEmpresa(int $empresaId): array
    {
        $stmt = $this->pdo->prepare(
            'SELECT o.id,
                    o.empresa_id,
                    o.titulo,
                    o.descricao,
                    o.requisitos,
                    o.area_conhecimento,
                    o.modalidade,
                    o.tipo_oportunidade,
                    o.cidade,
                    o.estado,
                    o.status,
                    o.data_publicacao,
                    o.data_encerramento,
                    o.criado_em,
                    o.atualizado_em,
                    COALESCE(e.nome_fantasia, e.razao_social) AS empresa_nome,
                    COUNT(i.id) AS total_inscricoes
             FROM oportunidades o
             INNER JOIN empresas e ON e.id = o.empresa_id
             LEFT JOIN inscricoes i ON i.oportunidade_id = o.id
             WHERE o.empresa_id = :empresa_id
             GROUP BY o.id,
                      o.empresa_id,
                      o.titulo,
                      o.descricao,
                      o.requisitos,
                      o.area_conhecimento,
                      o.modalidade,
                      o.tipo_oportunidade,
                      o.cidade,
                      o.estado,
                      o.status,
                      o.data_publicacao,
                      o.data_encerramento,
                      o.criado_em,
                      o.atualizado_em,
                      e.nome_fantasia,
                      e.razao_social
             ORDER BY o.atualizado_em DESC, o.id DESC'
        );

        $stmt->bindValue(':empresa_id', $empresaId, PDO::PARAM_INT);
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

    public function buscarPorIdEEmpresa(int $id, int $empresaId): ?array
    {
        $stmt = $this->pdo->prepare(
            'SELECT id,
                    empresa_id,
                    titulo,
                    descricao,
                    requisitos,
                    area_conhecimento,
                    modalidade,
                    tipo_oportunidade,
                    cidade,
                    estado,
                    status,
                    data_publicacao,
                    data_encerramento
             FROM oportunidades
             WHERE id = :id
               AND empresa_id = :empresa_id
             LIMIT 1'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->bindValue(':empresa_id', $empresaId, PDO::PARAM_INT);
        $stmt->execute();

        $oportunidade = $stmt->fetch();

        return $oportunidade ?: null;
    }

    public function criarCompleta(array $dados): int
    {
        $stmt = $this->pdo->prepare(
            'INSERT INTO oportunidades
                (empresa_id,
                 titulo,
                 descricao,
                 requisitos,
                 area_conhecimento,
                 modalidade,
                 tipo_oportunidade,
                 cidade,
                 estado,
                 status,
                 data_publicacao,
                 data_encerramento,
                 criado_em)
             VALUES
                (:empresa_id,
                 :titulo,
                 :descricao,
                 :requisitos,
                 :area_conhecimento,
                 :modalidade,
                 :tipo_oportunidade,
                 :cidade,
                 :estado,
                 :status,
                 :data_publicacao,
                 :data_encerramento,
                 NOW())'
        );

        $stmt->bindValue(':empresa_id', $dados['empresa_id'], PDO::PARAM_INT);
        $stmt->bindValue(':titulo', $dados['titulo']);
        $stmt->bindValue(':descricao', $dados['descricao']);
        $stmt->bindValue(':requisitos', $dados['requisitos']);
        $stmt->bindValue(':area_conhecimento', $dados['area_conhecimento']);
        $stmt->bindValue(':modalidade', $dados['modalidade']);
        $stmt->bindValue(':tipo_oportunidade', $dados['tipo_oportunidade']);
        $stmt->bindValue(':cidade', $dados['cidade']);
        $stmt->bindValue(':estado', $dados['estado']);
        $stmt->bindValue(':status', $dados['status']);
        $stmt->bindValue(':data_publicacao', $dados['data_publicacao']);
        $stmt->bindValue(':data_encerramento', $dados['data_encerramento']);
        $stmt->execute();

        return (int) $this->pdo->lastInsertId();
    }

    public function atualizarCompleta(int $id, array $dados): void
    {
        $stmt = $this->pdo->prepare(
            'UPDATE oportunidades
             SET empresa_id = :empresa_id,
                 titulo = :titulo,
                 descricao = :descricao,
                 requisitos = :requisitos,
                 area_conhecimento = :area_conhecimento,
                 modalidade = :modalidade,
                 tipo_oportunidade = :tipo_oportunidade,
                 cidade = :cidade,
                 estado = :estado,
                 status = :status,
                 data_publicacao = :data_publicacao,
                 data_encerramento = :data_encerramento
             WHERE id = :id'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->bindValue(':empresa_id', $dados['empresa_id'], PDO::PARAM_INT);
        $stmt->bindValue(':titulo', $dados['titulo']);
        $stmt->bindValue(':descricao', $dados['descricao']);
        $stmt->bindValue(':requisitos', $dados['requisitos']);
        $stmt->bindValue(':area_conhecimento', $dados['area_conhecimento']);
        $stmt->bindValue(':modalidade', $dados['modalidade']);
        $stmt->bindValue(':tipo_oportunidade', $dados['tipo_oportunidade']);
        $stmt->bindValue(':cidade', $dados['cidade']);
        $stmt->bindValue(':estado', $dados['estado']);
        $stmt->bindValue(':status', $dados['status']);
        $stmt->bindValue(':data_publicacao', $dados['data_publicacao']);
        $stmt->bindValue(':data_encerramento', $dados['data_encerramento']);
        $stmt->execute();
    }

    public function alterarStatus(int $id, string $status): void
    {
        $dataPublicacaoSql = '';
        $dataEncerramentoSql = '';

        if ($status === 'publicada') {
            $dataPublicacaoSql = ', data_publicacao = COALESCE(data_publicacao, NOW())';
        }

        if ($status === 'encerrada') {
            $dataEncerramentoSql = ', data_encerramento = COALESCE(data_encerramento, NOW())';
        }

        $stmt = $this->pdo->prepare(
            'UPDATE oportunidades
             SET status = :status'
             . $dataPublicacaoSql
             . $dataEncerramentoSql .
             ' WHERE id = :id'
        );

        $stmt->bindValue(':status', $status);
        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();
    }

    public function excluirSemInscricoes(int $id): bool
    {
        $stmt = $this->pdo->prepare(
            'DELETE FROM oportunidades
             WHERE id = :id
               AND NOT EXISTS (
                   SELECT 1
                   FROM inscricoes i
                   WHERE i.oportunidade_id = oportunidades.id
               )'
        );

        $stmt->bindValue(':id', $id, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->rowCount() > 0;
    }

    public function criar(
        int $empresaId,
        string $titulo,
        string $descricao,
        string $areaConhecimento,
        string $status = 'rascunho'
    ): int {
        return $this->criarCompleta([
            'empresa_id' => $empresaId,
            'titulo' => $titulo,
            'descricao' => $descricao,
            'requisitos' => null,
            'area_conhecimento' => $areaConhecimento,
            'modalidade' => 'presencial',
            'tipo_oportunidade' => 'estagio',
            'cidade' => null,
            'estado' => null,
            'status' => $status,
            'data_publicacao' => $status === 'publicada' ? date('Y-m-d H:i:s') : null,
            'data_encerramento' => null,
        ]);
    }
}