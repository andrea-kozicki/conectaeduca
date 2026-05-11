<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;

final class RelatorioService
{
    public function resumoGeral(): array
    {
        $pdo = Database::connect();

        return [
            'usuarios' => (int) $pdo->query('SELECT COUNT(*) FROM usuarios')->fetchColumn(),
            'empresas' => (int) $pdo->query('SELECT COUNT(*) FROM empresas')->fetchColumn(),
            'oportunidades' => (int) $pdo->query('SELECT COUNT(*) FROM oportunidades')->fetchColumn(),
            'inscricoes' => (int) $pdo->query('SELECT COUNT(*) FROM inscricoes')->fetchColumn(),
        ];
    }
}