<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\InscricaoService;

final class InscricaoController
{
    public function minhas(): void
    {
        $user = Authorization::requireAuth();

        $service = new InscricaoService();
        $inscricoes = $service->listarPorUsuario((int) $user['id']);

        View::render('inscricao/minhas-inscricoes', [
            'inscricoes' => $inscricoes,
        ]);
    }

    public function criar(): void
    {
        $user = Authorization::requireAuth();

        Csrf::requireValid($_POST['csrf_token'] ?? null);

        $service = new InscricaoService();
        $id = $service->inscrever((int) $user['id'], $_POST);

        Response::json([
            'ok' => true,
            'message' => 'Inscrição realizada com sucesso.',
            'id' => $id,
        ]);
    }

    public function atualizarStatus(): void
    {
        Authorization::requireAnyRole(['empresa', 'admin']);

        Csrf::requireValid($_POST['csrf_token'] ?? null);

        $service = new InscricaoService();
        $service->atualizarStatus($_POST);

        Response::json([
            'ok' => true,
            'message' => 'Status atualizado com sucesso.',
        ]);
    }
}