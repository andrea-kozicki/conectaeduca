<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\UsuarioService;

final class UsuarioController
{
    public function cadastro(): void
    {
        View::render('usuario/cadastro');
    }

    public function salvarCadastro(): void
    {
        Csrf::requireValid($_POST['csrf_token'] ?? null);

        $service = new UsuarioService();
        $id = $service->criarLocal($_POST);

        Response::json([
            'ok' => true,
            'message' => 'Usuário cadastrado com sucesso.',
            'id' => $id,
        ]);
    }

    public function dashboard(): void
    {
        $user = Authorization::requireAuth();

        View::render('usuario/dashboard', [
            'user' => $user,
        ]);
    }
}