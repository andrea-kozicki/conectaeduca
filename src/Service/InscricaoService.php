<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\InscricaoRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\InputValidator;
use RuntimeException;

final class InscricaoService
{
    private InscricaoRepository $inscricoes;

    public function __construct()
    {
        $this->inscricoes = new InscricaoRepository(Database::connect());
    }

    public function listarPorUsuario(int $usuarioId): array
    {
        return $this->inscricoes->listarPorUsuario($usuarioId);
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