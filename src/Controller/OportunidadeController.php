<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\OportunidadeService;
use Throwable;

final class OportunidadeController
{
    public function listar(): void
    {
        $service = new OportunidadeService();

        $oportunidades = $service->listarPublicas([
            'area' => $_GET['area'] ?? null,
            'busca' => $_GET['busca'] ?? null,
            'modalidade' => $_GET['modalidade'] ?? null,
            'tipo' => $_GET['tipo'] ?? null,
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

    public function gerenciarEmpresa(): void
    {
        $user = Authorization::requireAnyRole(['empresa', 'admin']);

        try {
            $service = new OportunidadeService();

            View::render('empresa/oportunidades', [
                'oportunidades' => $service->listarGerenciaveisParaEmpresaOuAdmin($user),
                'empresas' => $service->listarEmpresasParaFormulario($user),
                'success' => $_GET['ok'] ?? null,
                'error' => $_GET['erro'] ?? null,
            ]);
        } catch (Throwable $e) {
            View::render('empresa/oportunidades', [
                'oportunidades' => [],
                'empresas' => [],
                'success' => null,
                'error' => $e->getMessage(),
            ]);
        }
    }

    public function processarGestaoEmpresa(): void
    {
        $user = Authorization::requireAnyRole(['empresa', 'admin']);

        try {
            Csrf::requireValid($_POST['csrf_token'] ?? null);

            $service = new OportunidadeService();
            $action = $_POST['action'] ?? '';

            match ($action) {
                'criar' => $service->criarGerenciavel($user, $_POST),
                'atualizar' => $service->atualizarGerenciavel($user, $_POST),
                'status' => $service->alterarStatusGerenciavel($user, $_POST),
                'excluir' => $service->excluirGerenciavel($user, $_POST),
                default => throw new \RuntimeException('Ação inválida.'),
            };

            header('Location: /empresa/oportunidades.php?ok=' . rawurlencode('Operação realizada com sucesso.'));
            exit;
        } catch (Throwable $e) {
            header('Location: /empresa/oportunidades.php?erro=' . rawurlencode($e->getMessage()));
            exit;
        }
    }

    public function criar(): void
    {
        $user = Authorization::requireAnyRole(['empresa', 'admin']);
        Csrf::requireValid($_POST['csrf_token'] ?? null);

        $service = new OportunidadeService();
        $id = $service->criar($_POST, $user);

        Response::json([
            'ok' => true,
            'message' => 'Oportunidade criada com sucesso.',
            'id' => $id,
        ]);
    }
}