<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\InscricaoService;
use Throwable;

final class InscricaoController
{
    public function minhas(): void
    {
        $user = Authorization::requireAuth();

        $service = new InscricaoService();
        $inscricoes = $service->listarPorUsuario((int) $user['id']);

        View::render('inscricao/minhas-inscricoes', [
            'inscricoes' => $inscricoes,
            'success' => ($_GET['cancelada'] ?? '') === '1'
                ? 'Candidatura cancelada com sucesso.'
                : null,
            'error' => $_GET['erro'] ?? null,
        ]);
    }

    public function recebidasEmpresa(): void
    {
        $user = Authorization::requireAnyRole(['empresa', 'admin']);

        try {
            $service = new InscricaoService();
            $inscricoes = $service->listarRecebidasParaEmpresaOuAdmin($user);

            View::render('empresa/inscricoes', [
                'inscricoes' => $inscricoes,
                'success' => ($_GET['atualizada'] ?? '') === '1'
                    ? 'Status da inscrição atualizado com sucesso.'
                    : null,
                'error' => $_GET['erro'] ?? null,
            ]);
        } catch (Throwable $e) {
            View::render('empresa/inscricoes', [
                'inscricoes' => [],
                'success' => null,
                'error' => $e->getMessage(),
            ]);
        }
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

    public function cancelar(): void
    {
        $user = Authorization::requireAuth();

        try {
            Csrf::requireValid($_POST['csrf_token'] ?? null);

            $service = new InscricaoService();
            $service->cancelarPorUsuario((int) $user['id'], $_POST);

            header('Location: /api/inscricoes.php?cancelada=1');
            exit;
        } catch (Throwable $e) {
            header('Location: /api/inscricoes.php?erro=' . rawurlencode($e->getMessage()));
            exit;
        }
    }

    public function atualizarStatusEmpresa(): void
    {
        $user = Authorization::requireAnyRole(['empresa', 'admin']);

        try {
            Csrf::requireValid($_POST['csrf_token'] ?? null);

            $service = new InscricaoService();
            $service->atualizarStatusPorEmpresaOuAdmin($user, $_POST);

            header('Location: /empresa/inscricoes.php?atualizada=1');
            exit;
        } catch (Throwable $e) {
            header('Location: /empresa/inscricoes.php?erro=' . rawurlencode($e->getMessage()));
            exit;
        }
    }

    public function atualizarStatus(): void
    {
        $user = Authorization::requireAnyRole(['empresa', 'admin']);

        Csrf::requireValid($_POST['csrf_token'] ?? null);

        $service = new InscricaoService();
        $service->atualizarStatusPorEmpresaOuAdmin($user, $_POST);

        Response::json([
            'ok' => true,
            'message' => 'Status atualizado com sucesso.',
        ]);
    }
}