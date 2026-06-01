<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\FaleConoscoService;
use ConectaEduca\Core\SecureFormRequest;
use Throwable;

final class FaleConoscoController
{
    public function formulario(): void
    {
        $user = Authorization::requireAuth();

        try {
            $service = new FaleConoscoService();

            View::render('contato/fale_conosco', [
                'mensagens' => $service->listarDoUsuario($user),
                'success' => $_GET['ok'] ?? null,
                'error' => $_GET['erro'] ?? null,
            ]);
        } catch (Throwable $e) {
            View::render('contato/fale_conosco', [
                'mensagens' => [],
                'success' => null,
                'error' => $e->getMessage(),
            ]);
        }
    }

    public function enviar(): void
    {
        $user = Authorization::requireAuth();

        try {
            $dados = SecureFormRequest::data();

            Csrf::requireValid(SecureFormRequest::csrfToken($dados));

            $service = new FaleConoscoService();
            $service->enviar($user, $dados);

            header('Location: /fale_conosco.php?ok=' . rawurlencode('Mensagem enviada com criptografia híbrida.'));
            exit;
        } catch (Throwable $e) {
            header('Location: /fale_conosco.php?erro=' . rawurlencode($e->getMessage()));
            exit;
        }
    }

    public function adminListar(): void
    {
        Authorization::requireRole('admin');

        try {
            $service = new FaleConoscoService();

            View::render('admin/mensagens_contato', [
                'mensagens' => $service->listarParaAdminComTexto(),
                'success' => $_GET['ok'] ?? null,
                'error' => $_GET['erro'] ?? null,
            ]);
        } catch (Throwable $e) {
            View::render('admin/mensagens_contato', [
                'mensagens' => [],
                'success' => null,
                'error' => $e->getMessage(),
            ]);
        }
    }
}