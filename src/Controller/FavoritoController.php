<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\FavoritoService;
use Throwable;

final class FavoritoController
{
    public function listar(): void
    {
        $user = Authorization::requireAuth();

        try {
            $service = new FavoritoService();

            View::render('usuario/favoritos', [
                'favoritos' => $service->listarPorUsuario((int) $user['id']),
                'success' => $_GET['ok'] ?? null,
                'error' => $_GET['erro'] ?? null,
            ]);
        } catch (Throwable $e) {
            View::render('usuario/favoritos', [
                'favoritos' => [],
                'success' => null,
                'error' => $e->getMessage(),
            ]);
        }
    }

    public function processar(): void
    {
        $user = Authorization::requireAuth();

        try {
            Csrf::requireValid($_POST['csrf_token'] ?? null);

            $service = new FavoritoService();
            $action = $_POST['action'] ?? 'alternar';

            if ($action === 'remover') {
                $service->remover($user, $_POST);
                $mensagem = 'Favorito removido com sucesso.';
            } else {
                $resultado = $service->alternar($user, $_POST);
                $mensagem = $resultado === 'adicionado'
                    ? 'Oportunidade adicionada aos favoritos.'
                    : 'Oportunidade removida dos favoritos.';
            }

            $fallback = '/favoritos.php?ok=' . rawurlencode($mensagem);

            header('Location: ' . $this->redirectSeguro($_POST['redirect_url'] ?? null, $fallback));
            exit;
        } catch (Throwable $e) {
            header('Location: /favoritos.php?erro=' . rawurlencode($e->getMessage()));
            exit;
        }
    }

    private function redirectSeguro(mixed $url, string $fallback): string
    {
        $url = trim((string) $url);

        if ($url === '') {
            return $fallback;
        }

        if (!str_starts_with($url, '/') || str_starts_with($url, '//')) {
            return $fallback;
        }

        if (str_contains($url, "\n") || str_contains($url, "\r")) {
            return $fallback;
        }

        $separador = str_contains($url, '?') ? '&' : '?';

        return $url . $separador . 'ok=' . rawurlencode('Favoritos atualizados.');
    }
}