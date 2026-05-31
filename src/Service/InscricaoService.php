<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\EmpresaRepository;
use ConectaEduca\Repository\InscricaoRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\InputValidator;
use RuntimeException;

final class InscricaoService
{
    private InscricaoRepository $inscricoes;
    private EmpresaRepository $empresas;

    public function __construct()
    {
        $pdo = Database::connect();

        $this->inscricoes = new InscricaoRepository($pdo);
        $this->empresas = new EmpresaRepository($pdo);
    }

    public function listarPorUsuario(int $usuarioId): array
    {
        return $this->inscricoes->listarPorUsuario($usuarioId);
    }

    public function listarRecebidasParaEmpresaOuAdmin(array $user): array
    {
        if (($user['role'] ?? '') === 'admin') {
            return $this->inscricoes->listarRecebidasTodas();
        }

        $empresa = $this->empresas->buscarPorUsuarioId((int) $user['id']);

        if ($empresa === null) {
            throw new RuntimeException('Nenhuma empresa está vinculada a este usuário.');
        }

        return $this->inscricoes->listarRecebidasPorEmpresa((int) $empresa['id']);
    }

    public function inscrever(int $usuarioId, array $dados): int
    {
        $oportunidadeId = InputValidator::id($dados['oportunidade_id'] ?? null, 'oportunidade_id');

        if ($this->inscricoes->existe($usuarioId, $oportunidadeId)) {
            throw new RuntimeException('Usuário já inscrito nesta oportunidade.');
        }

        $id = $this->inscricoes->criar($usuarioId, $oportunidadeId);

        AuditLogger::log('inscricao_criada', [
            'usuario_id' => $usuarioId,
            'oportunidade_id' => $oportunidadeId,
        ]);

        return $id;
    }

    public function cancelarPorUsuario(int $usuarioId, array $dados): void
    {
        $id = InputValidator::id($dados['id'] ?? null, 'id');

        $inscricao = $this->inscricoes->buscarPorIdEUsuario($id, $usuarioId);

        if ($inscricao === null) {
            throw new RuntimeException('Inscrição não encontrada para este usuário.');
        }

        $statusAtual = (string) ($inscricao['status'] ?? '');

        if (!in_array($statusAtual, ['enviada', 'em_analise'], true)) {
            throw new RuntimeException('Esta candidatura não pode mais ser cancelada.');
        }

        $cancelou = $this->inscricoes->cancelarPorUsuario($id, $usuarioId);

        if (!$cancelou) {
            throw new RuntimeException('Não foi possível cancelar a candidatura.');
        }

        AuditLogger::log('inscricao_cancelada_pelo_usuario', [
            'inscricao_id' => $id,
            'usuario_id' => $usuarioId,
            'oportunidade_id' => $inscricao['oportunidade_id'] ?? null,
            'status_anterior' => $statusAtual,
            'status_novo' => 'cancelada_pelo_usuario',
        ]);
    }

    public function atualizarStatusPorEmpresaOuAdmin(array $user, array $dados): void
    {
        $id = InputValidator::id($dados['id'] ?? null, 'id');

        $status = InputValidator::enum(
            $dados['status'] ?? '',
            ['em_analise', 'aprovada', 'rejeitada', 'encerrada'],
            'status'
        );

        $observacoes = InputValidator::optionalString(
            $dados['observacoes_empresa'] ?? null,
            1000
        );

        if ($observacoes === null) {
            throw new RuntimeException('Informe uma observação para justificar a alteração de status.');
        }

        $empresaId = null;

        if (($user['role'] ?? '') === 'admin') {
            $inscricao = $this->inscricoes->buscarPorId($id);
        } else {
            $empresa = $this->empresas->buscarPorUsuarioId((int) $user['id']);

            if ($empresa === null) {
                throw new RuntimeException('Nenhuma empresa está vinculada a este usuário.');
            }

            $empresaId = (int) $empresa['id'];
            $inscricao = $this->inscricoes->buscarPorIdEEmpresa($id, $empresaId);
        }

        if ($inscricao === null) {
            throw new RuntimeException('Inscrição não encontrada ou não autorizada para este perfil.');
        }

        $statusAnterior = (string) ($inscricao['status'] ?? '');

        if ($statusAnterior === 'cancelada_pelo_usuario') {
            throw new RuntimeException('Candidatura cancelada pelo usuário não pode ser alterada pela empresa.');
        }

        $this->inscricoes->atualizarStatusComObservacao($id, $status, $observacoes);

        AuditLogger::log('inscricao_status_atualizado_por_empresa', [
            'inscricao_id' => $id,
            'usuario_id' => $user['id'] ?? null,
            'role' => $user['role'] ?? null,
            'empresa_id' => $empresaId,
            'status_anterior' => $statusAnterior,
            'status_novo' => $status,
            'observacao_informada' => true,
            'observacao_tamanho' => mb_strlen($observacoes),
        ]);
    }

    public function atualizarStatus(array $dados): void
    {
        $id = InputValidator::id($dados['id'] ?? null, 'id');

        $status = InputValidator::enum(
            $dados['status'] ?? '',
            ['enviada', 'em_analise', 'aprovada', 'rejeitada', 'cancelada_pelo_usuario', 'encerrada'],
            'status'
        );

        $this->inscricoes->atualizarStatus($id, $status);

        AuditLogger::log('inscricao_status_atualizado', [
            'inscricao_id' => $id,
            'status' => $status,
        ]);
    }
}