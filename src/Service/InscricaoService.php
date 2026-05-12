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