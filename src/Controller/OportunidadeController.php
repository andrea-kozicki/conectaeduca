<?php
declare(strict_types=1);

namespace ConectaEduca\Controller;

use ConectaEduca\Core\Response;
use ConectaEduca\Core\SecureFormRequest;
use ConectaEduca\Core\View;
use ConectaEduca\Security\Authorization;
use ConectaEduca\Security\Csrf;
use ConectaEduca\Service\OportunidadeService;
use ConectaEduca\Service\FavoritoService;
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

        $favoritoIds = [];
        $user = Authorization::user();

        if ($user !== null && ($user['role'] ?? '') !== 'empresa') {
            $favoritoIds = (new FavoritoService())->idsFavoritadosPorUsuario((int) $user['id']);
        }

        View::render('oportunidade/listar', [
            'oportunidades' => $oportunidades,
            'favoritoIds' => $favoritoIds,
            'currentUser' => $user,
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

        $user = Authorization::user();

        if (($oportunidade['status'] ?? '') !== 'publicada'
            && (($user['role'] ?? null) !== 'admin')) {
            Response::notFound();
        }

        $favoritoIds = [];

        if ($user !== null && ($user['role'] ?? '') !== 'empresa') {
            $favoritoIds = (new FavoritoService())->idsFavoritadosPorUsuario((int) $user['id']);
        }

        View::render('oportunidade/detalhe', [
            'oportunidade' => $oportunidade,
            'favoritoIds' => $favoritoIds,
            'currentUser' => $user,
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
            $dados = SecureFormRequest::data();

            Csrf::requireValid(SecureFormRequest::csrfToken($dados));

            $service = new OportunidadeService();
            $action = $dados['action'] ?? '';

            match ($action) {
                'criar' => $service->criarGerenciavel($user, $dados),
                'atualizar' => $service->atualizarGerenciavel($user, $dados),
                'status' => $service->alterarStatusGerenciavel($user, $dados),
                'excluir' => $service->excluirGerenciavel($user, $dados),
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
        $dados = SecureFormRequest::data();

        Csrf::requireValid(SecureFormRequest::csrfToken($dados));

        $service = new OportunidadeService();
        $id = $service->criar($dados, $user);

        Response::json([
            'ok' => true,
            'message' => 'Oportunidade criada com sucesso.',
            'id' => $id,
        ]);
    }
}