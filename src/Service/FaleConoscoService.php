<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\FaleConoscoRepository;
use ConectaEduca\Security\AuditLogger;
use ConectaEduca\Security\CryptoHybrid;
use RuntimeException;

final class FaleConoscoService
{
    private FaleConoscoRepository $mensagens;

    private const CATEGORIAS = [
        'duvida',
        'suporte',
        'privacidade',
        'seguranca',
        'acessibilidade',
        'outro',
    ];

    public function __construct()
    {
        $this->mensagens = new FaleConoscoRepository(Database::connect());
    }

    public function listarDoUsuario(array $user): array
    {
        return $this->mensagens->listarPorUsuario($this->usuarioId($user));
    }

    public function enviar(array $user, array $dados): int
    {
        $usuarioId = $this->usuarioId($user);

        $assunto = trim((string) ($dados['assunto'] ?? ''));
        $categoria = trim((string) ($dados['categoria'] ?? 'outro'));
        $mensagem = trim((string) ($dados['mensagem'] ?? ''));

        if (mb_strlen($assunto) < 5 || mb_strlen($assunto) > 160) {
            throw new RuntimeException('O assunto deve ter entre 5 e 160 caracteres.');
        }

        if (!in_array($categoria, self::CATEGORIAS, true)) {
            throw new RuntimeException('Categoria inválida.');
        }

        if (mb_strlen($mensagem) < 10 || mb_strlen($mensagem) > 4000) {
            throw new RuntimeException('A mensagem deve ter entre 10 e 4000 caracteres.');
        }

        $envelope = CryptoHybrid::encryptString($mensagem);

        $id = $this->mensagens->criar(
            $usuarioId,
            $assunto,
            $categoria,
            $envelope
        );

        AuditLogger::log('mensagem_contato_criptografada_enviada', [
            'mensagem_id' => $id,
            'usuario_id' => $usuarioId,
            'role' => $user['role'] ?? null,
            'categoria' => $categoria,
            'algoritmo' => $envelope['algorithm'] ?? null,
            'tamanho_plaintext' => mb_strlen($mensagem),
            'ciphertext_tamanho' => strlen($envelope['ciphertext'] ?? ''),
        ]);

        return $id;
    }

    public function listarParaAdminComTexto(): array
    {
        $mensagens = $this->mensagens->listarTodasParaAdmin();

        return array_map(
            static function (array $mensagem): array {
                try {
                    $mensagem['mensagem_descriptografada'] = CryptoHybrid::decryptString([
                        'algorithm' => $mensagem['algoritmo'] ?? null,
                        'encrypted_key' => $mensagem['encrypted_key'],
                        'iv' => $mensagem['iv'],
                        'tag' => $mensagem['tag'],
                        'ciphertext' => $mensagem['ciphertext'],
                    ]);
                    $mensagem['erro_descriptografia'] = null;
                } catch (\Throwable $e) {
                    $mensagem['mensagem_descriptografada'] = '';
                    $mensagem['erro_descriptografia'] = $e->getMessage();
                }

                return $mensagem;
            },
            $mensagens
        );
    }

    private function usuarioId(array $user): int
    {
        $usuarioId = (int) ($user['id'] ?? 0);

        if ($usuarioId <= 0) {
            throw new RuntimeException('Usuário autenticado inválido.');
        }

        return $usuarioId;
    }
}