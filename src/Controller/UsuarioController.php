<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Security\SecureSession;
use ConectaEduca\Service\UsuarioService;
use Throwable;

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

    public function perfil(): void
    {
        $sessionUser = Authorization::requireAuth();

        $service = new UsuarioService();
        $usuario = $service->buscarPorId((int) $sessionUser['id']);

        if ($usuario === null) {
            http_response_code(404);
            exit('Usuário não encontrado.');
        }

        View::render('usuario/perfil', [
            'usuario' => $usuario,
            'success' => ($_GET['atualizado'] ?? '') === '1'
                ? 'Perfil atualizado com sucesso.'
                : null,
            'error' => null,
        ]);
    }

    public function atualizarPerfil(): void
    {
        $sessionUser = Authorization::requireAuth();

        try {
            Csrf::requireValid($_POST['csrf_token'] ?? null);

            $service = new UsuarioService();
            $usuario = $service->atualizarPerfil((int) $sessionUser['id'], $_POST);

            SecureSession::start();

            $_SESSION['user'] = array_merge($_SESSION['user'] ?? [], [
                'id' => $usuario['id'],
                'nome' => $usuario['nome'],
                'email' => $usuario['email'],
                'role' => $usuario['role'],
            ]);

            AuditLogger::log('perfil_usuario_atualizado', [
                'usuario_id' => $usuario['id'],
            ]);

            header('Location: /perfil.php?atualizado=1');
            exit;
        } catch (Throwable $e) {
            AuditLogger::log('perfil_usuario_erro_atualizacao', [
                'usuario_id' => $sessionUser['id'] ?? null,
                'erro' => $e->getMessage(),
            ]);

            $service = new UsuarioService();
            $usuario = $service->buscarPorId((int) $sessionUser['id']) ?? $sessionUser;

            View::render('usuario/perfil', [
                'usuario' => $usuario,
                'success' => null,
                'error' => $e->getMessage(),
            ]);
        }
    }
}