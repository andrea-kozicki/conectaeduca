<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\OportunidadeService;

final class OportunidadeController
{
    public function listar(): void
    {
        $service = new OportunidadeService();

        $oportunidades = $service->listarPublicas([
            'area' => $_GET['area'] ?? null,
            'busca' => $_GET['busca'] ?? null,
        ]);

        View::render('oportunidade/listar', [
            'oportunidades' => $oportunidades,
        ]);
    }

    public function detalhe(): void
    {
        $id = (int) ($_GET['id'] ?? 0);

        $service = new OportunidadeService();
        $oportunidade = $service->buscarPorId($id);

        if ($oportunidade === null) {
            Response::notFound();
        }

        View::render('oportunidade/detalhe', [
            'oportunidade' => $oportunidade,
        ]);
    }

    public function criar(): void
    {
        Authorization::requireAnyRole(['empresa', 'admin']);
        Csrf::requireValid($_POST['csrf_token'] ?? null);

        $service = new OportunidadeService();
        $id = $service->criar($_POST);

        Response::json([
            'ok' => true,
            'message' => 'Oportunidade criada com sucesso.',
            'id' => $id,
        ]);
    }
}