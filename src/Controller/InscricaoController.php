<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\SecureFormRequest;
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

        $dados = SecureFormRequest::data();

        Csrf::requireValid(SecureFormRequest::csrfToken($dados));

        $service = new InscricaoService();
        $id = $service->inscrever((int) $user['id'], $dados);

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
            $dados = SecureFormRequest::data();

            Csrf::requireValid(SecureFormRequest::csrfToken($dados));

            $service = new InscricaoService();
            $service->cancelarPorUsuario((int) $user['id'], $dados);

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
            $dados = SecureFormRequest::data();

            Csrf::requireValid(SecureFormRequest::csrfToken($dados));

            $service = new InscricaoService();
            $service->atualizarStatusPorEmpresaOuAdmin($user, $dados);

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

        $dados = SecureFormRequest::data();

        Csrf::requireValid(SecureFormRequest::csrfToken($dados));

        $service = new InscricaoService();
        $service->atualizarStatusPorEmpresaOuAdmin($user, $dados);

        Response::json([
            'ok' => true,
            'message' => 'Status atualizado com sucesso.',
        ]);
    }
}