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

        $modalidade = InputValidator::optionalString($filtros['modalidade'] ?? null, 20);

        if ($modalidade !== null) {
            $modalidade = InputValidator::enum(
                $modalidade,
                ['presencial', 'remoto', 'hibrido'],
                'modalidade'
            );
        }

        $tipo = InputValidator::optionalString($filtros['tipo'] ?? null, 30);

        if ($tipo !== null) {
            $tipo = InputValidator::enum(
                $tipo,
                ['estagio', 'emprego', 'trainee', 'bolsa', 'voluntariado', 'outro'],
                'tipo'
            );
        }

        return $this->oportunidades->listarPublicas($area, $busca, $modalidade, $tipo);
    }
}    