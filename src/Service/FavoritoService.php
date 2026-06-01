<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\FavoritoRepository;
use ConectaEduca\Repository\OportunidadeRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\InputValidator;
use RuntimeException;

final class FavoritoService
{
    private FavoritoRepository $favoritos;
    private OportunidadeRepository $oportunidades;

    public function __construct()
    {
        $pdo = Database::connect();

        $this->favoritos = new FavoritoRepository($pdo);
        $this->oportunidades = new OportunidadeRepository($pdo);
    }

    public function listarPorUsuario(int $usuarioId): array
    {
        return $this->favoritos->listarPorUsuario($usuarioId);
    }

    public function idsFavoritadosPorUsuario(int $usuarioId): array
    {
        return $this->favoritos->idsFavoritadosPorUsuario($usuarioId);
    }

    public function alternar(array $user, array $dados): string
    {
        $this->validarPerfil($user);

        $usuarioId = (int) ($user['id'] ?? 0);
        $oportunidadeId = InputValidator::id($dados['oportunidade_id'] ?? null, 'oportunidade_id');

        if ($this->favoritos->existe($usuarioId, $oportunidadeId)) {
            $this->favoritos->remover($usuarioId, $oportunidadeId);

            AuditLogger::log('favorito_removido', [
                'usuario_id' => $usuarioId,
                'role' => $user['role'] ?? null,
                'oportunidade_id' => $oportunidadeId,
            ]);

            return 'removido';
        }

        $this->validarOportunidadePublicada($oportunidadeId);

        $this->favoritos->adicionar($usuarioId, $oportunidadeId);

        AuditLogger::log('favorito_adicionado', [
            'usuario_id' => $usuarioId,
            'role' => $user['role'] ?? null,
            'oportunidade_id' => $oportunidadeId,
        ]);

        return 'adicionado';
    }

    public function remover(array $user, array $dados): void
    {
        $this->validarPerfil($user);

        $usuarioId = (int) ($user['id'] ?? 0);
        $oportunidadeId = InputValidator::id($dados['oportunidade_id'] ?? null, 'oportunidade_id');

        $removeu = $this->favoritos->remover($usuarioId, $oportunidadeId);

        if ($removeu) {
            AuditLogger::log('favorito_removido', [
                'usuario_id' => $usuarioId,
                'role' => $user['role'] ?? null,
                'oportunidade_id' => $oportunidadeId,
            ]);
        }
    }

    private function validarOportunidadePublicada(int $oportunidadeId): void
    {
        $oportunidade = $this->oportunidades->buscarPorId($oportunidadeId);

        if ($oportunidade === null) {
            throw new RuntimeException('Oportunidade não encontrada.');
        }

        if (($oportunidade['status'] ?? '') !== 'publicada') {
            throw new RuntimeException('Somente oportunidades publicadas podem ser favoritadas.');
        }
    }

    private function validarPerfil(array $user): void
    {
        if (($user['role'] ?? '') === 'empresa') {
            throw new RuntimeException('Perfil empresa deve gerenciar oportunidades, não favoritar.');
        }
    }
}