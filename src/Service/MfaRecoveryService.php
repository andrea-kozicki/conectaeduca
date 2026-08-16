<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use ConectaEduca\Config\Database;
use ConectaEduca\Repository\MfaRecoveryRepository;
use ConectaEduca\Repository\MfaRecoveryStore;
use DomainException;
use RuntimeException;

final class MfaRecoveryService
{
    private const QUANTIDADE_CODIGOS = 10;
    private const BYTES_POR_CODIGO = 10;

    private MfaRecoveryStore $codigos;

    public function __construct(
        ?MfaRecoveryStore $codigos = null
    ) {
        $this->codigos = $codigos
            ?? new MfaRecoveryRepository(
                Database::connect()
            );
    }

    /**
     * Gera novos códigos e invalida o conjunto anterior.
     *
     * @return list<string> Códigos puros, retornados uma única vez.
     */
    public function gerarParaUsuario(
        int $usuarioId
    ): array {
        if ($usuarioId < 1) {
            throw new DomainException(
                'Usuário inválido para códigos de recuperação.'
            );
        }

        $codigos = [];
        $hashes = [];

        while (count($codigos) < self::QUANTIDADE_CODIGOS) {
            $codigo = self::gerarCodigo();

            if (in_array($codigo, $codigos, true)) {
                continue;
            }

            $hash = password_hash(
                self::normalizarCodigo($codigo),
                PASSWORD_DEFAULT
            );

            if (!is_string($hash) || $hash === '') {
                throw new RuntimeException(
                    'Não foi possível proteger o código de recuperação.'
                );
            }

            $codigos[] = $codigo;
            $hashes[] = $hash;
        }

        $this->codigos->substituirCodigos(
            $usuarioId,
            $hashes
        );

        return $codigos;
    }

    public function validarEConsumir(
        int $usuarioId,
        string $codigo
    ): bool {
        if ($usuarioId < 1) {
            return false;
        }

        $normalizado = self::normalizarCodigo(
            $codigo
        );

        if ($normalizado === null) {
            return false;
        }

        foreach (
            $this->codigos->buscarAtivos($usuarioId)
            as $registro
        ) {
            if (
                !password_verify(
                    $normalizado,
                    $registro['codigo_hash']
                )
            ) {
                continue;
            }

            /*
             * A atualização condicionada a usado_em IS NULL impede
             * que duas requisições concorrentes consumam o mesmo código.
             */
            return $this->codigos->marcarComoUsado(
                $usuarioId,
                $registro['id']
            );
        }

        return false;
    }

    public function quantidadeAtivos(
        int $usuarioId
    ): int {
        if ($usuarioId < 1) {
            return 0;
        }

        return $this->codigos->quantidadeAtivos(
            $usuarioId
        );
    }

    private static function gerarCodigo(): string
    {
        $hex = strtoupper(
            bin2hex(
                random_bytes(
                    self::BYTES_POR_CODIGO
                )
            )
        );

        return implode(
            '-',
            str_split($hex, 4)
        );
    }

    private static function normalizarCodigo(
        string $codigo
    ): ?string {
        $normalizado = strtoupper(
            preg_replace(
                '/[\s-]+/',
                '',
                trim($codigo)
            ) ?? ''
        );

        if (!preg_match('/^[A-F0-9]{20}$/', $normalizado)) {
            return null;
        }

        return $normalizado;
    }
}
