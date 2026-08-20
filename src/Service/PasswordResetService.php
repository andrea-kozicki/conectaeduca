<?php

declare(strict_types=1);

namespace ConectaEduca\Service;

use Closure;
use ConectaEduca\Config\Database;
use ConectaEduca\Repository\PasswordResetRepository;
use ConectaEduca\Repository\PasswordResetStore;
use DateTimeImmutable;
use DomainException;
use InvalidArgumentException;
use RuntimeException;

final class PasswordResetService
{
    private const TOKEN_BYTES = 32;
    private const TOKEN_TTL_MINUTES = 30;
    private const PASSWORD_MIN_LENGTH = 8;

    private PasswordResetStore $tokens;

    /** @var Closure():DateTimeImmutable */
    private Closure $clock;

    public function __construct(
        ?PasswordResetStore $tokens = null,
        ?callable $clock = null
    ) {
        $this->tokens = $tokens
            ?? new PasswordResetRepository(
                Database::connect()
            );

        $this->clock = Closure::fromCallable(
            $clock
                ?? static fn (): DateTimeImmutable =>
                    new DateTimeImmutable('now')
        );
    }

    /**
     * Emite um novo token e invalida qualquer token de recuperação anterior.
     *
     * O token puro é retornado somente ao chamador para que possa ser enviado
     * ao usuário. Apenas o SHA-256 é persistido no banco.
     *
     * @return array{token:string,expira_em:DateTimeImmutable}
     */
    public function emitirParaUsuario(
        int $usuarioId
    ): array {
        if ($usuarioId < 1) {
            throw new DomainException(
                'Usuário inválido para recuperação de senha.'
            );
        }

        $token = self::gerarToken();
        $tokenHash = self::hashToken($token);

        $agora = ($this->clock)();
        $expiraEm = $agora->modify(
            '+' . self::TOKEN_TTL_MINUTES . ' minutes'
        );

        $this->tokens->substituirToken(
            $usuarioId,
            $tokenHash,
            $expiraEm
        );

        return [
            'token' => $token,
            'expira_em' => $expiraEm,
        ];
    }

    /**
     * Retorna o usuário associado a um token ainda válido, sem consumi-lo.
     *
     * Isso permite abrir a tela de redefinição no GET sem destruir o token.
     */
    public function usuarioDoTokenValido(
        string $token
    ): ?int {
        if (!self::formatoValido($token)) {
            return null;
        }

        $registro = $this->tokens
            ->buscarAtivoPorHash(
                self::hashToken($token)
            );

        if ($registro === null) {
            return null;
        }

        return $registro['usuario_id'];
    }

    /**
     * Altera a senha e consome o token dentro da mesma transação do store.
     *
     * Token inválido/expirado/usado retorna null. Erros na nova senha são
     * tratados separadamente como entrada inválida do usuário.
     *
     * @return int|null ID do usuário quando a redefinição foi concluída.
     */
    public function redefinirSenha(
        string $token,
        string $senha,
        string $confirmarSenha
    ): ?int {
        if (!self::formatoValido($token)) {
            return null;
        }

        self::validarNovaSenha(
            $senha,
            $confirmarSenha
        );

        $senhaHash = password_hash(
            $senha,
            PASSWORD_DEFAULT
        );

        if (!is_string($senhaHash) || $senhaHash === '') {
            throw new RuntimeException(
                'Não foi possível proteger a nova senha.'
            );
        }

        return $this->tokens
            ->redefinirSenhaPorHash(
                self::hashToken($token),
                $senhaHash
            );
    }

    private static function validarNovaSenha(
        string $senha,
        string $confirmarSenha
    ): void {
        if (strlen($senha) < self::PASSWORD_MIN_LENGTH) {
            throw new InvalidArgumentException(
                'A senha deve ter pelo menos 8 caracteres.'
            );
        }

        if ($senha !== $confirmarSenha) {
            throw new InvalidArgumentException(
                'A confirmação de senha não confere.'
            );
        }
    }

    private static function gerarToken(): string
    {
        return rtrim(
            strtr(
                base64_encode(
                    random_bytes(self::TOKEN_BYTES)
                ),
                '+/',
                '-_'
            ),
            '='
        );
    }

    private static function formatoValido(
        string $token
    ): bool {
        $token = trim($token);

        /* 32 bytes em Base64URL sem padding resultam em 43 caracteres. */
        return preg_match(
            '/^[A-Za-z0-9_-]{43}$/',
            $token
        ) === 1;
    }

    private static function hashToken(
        string $token
    ): string {
        return hash(
            'sha256',
            trim($token)
        );
    }
}
