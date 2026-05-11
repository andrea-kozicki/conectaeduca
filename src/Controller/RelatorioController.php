<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Service\RelatorioService;

final class RelatorioController
{
    public function index(): void
    {
        Authorization::requireRole('admin');

        $service = new RelatorioService();

        View::render('admin/relatorio', [
            'resumo' => $service->resumoGeral(),
        ]);
    }

    public function json(): void
    {
        Authorization::requireRole('admin');

        $service = new RelatorioService();

        Response::json([
            'ok' => true,
            'data' => $service->resumoGeral(),
        ]);
    }
}