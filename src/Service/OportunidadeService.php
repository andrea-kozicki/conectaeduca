<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\OportunidadeRepository;
use ConectaEduca\Security\InputValidator;

final class OportunidadeService
{
    private OportunidadeRepository $oportunidades;

    public function __construct()
    {
        $this->oportunidades = new OportunidadeRepository(Database::connect());
    }

    public function listarPublicas(array $filtros = []): array
    {
        $area = InputValidator::optionalString($filtros['area'] ?? null, 120);
        $busca = InputValidator::searchTerm($filtros['busca'] ?? '', 100);

        return $this->oportunidades->listarPublicas($area, $busca);
    }

    public function buscarPorId(int $id): ?array
    {
        return $this->oportunidades->buscarPorId($id);
    }

    public function criar(array $dados): int
    {
        $empresaId = InputValidator::id($dados['empresa_id'] ?? null, 'empresa_id');
        $titulo = InputValidator::requiredString($dados['titulo'] ?? '', 'titulo', 180);
        $descricao = InputValidator::requiredString($dados['descricao'] ?? '', 'descricao', 3000);
        $area = InputValidator::requiredString($dados['area'] ?? $dados['area_conhecimento'] ?? '', 'area_conhecimento', 120);

        $status = InputValidator::enum(
            $dados['status'] ?? 'rascunho',
            ['rascunho', 'publicada', 'encerrada', 'suspensa'],
            'status'
        );

        return $this->oportunidades->criar($empresaId, $titulo, $descricao, $area, $status);
    }
}