<?php

declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Repository\PasswordResetStore;
use ConectaEduca\Service\PasswordResetService;
use DateTimeImmutable;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Tokens e redefinição de senha')]
final class PasswordResetServiceTest extends TestCase
{
    private PasswordResetStore $store;
    private PasswordResetService $service;

    protected function setUp(): void
    {
        $this->store = new class implements PasswordResetStore {
            /**
             * @var array<string,array{
             *     id:int,
             *     usuario_id:int,
             *     token_hash:string,
             *     expira_em:DateTimeImmutable,
             *     usado:bool
             * }>
             */
            public array $registros = [];

            /** @var array<int,string> */
            public array $senhas = [];

            public int $proximoId = 1;

            private DateTimeImmutable $agora;

            public function __construct()
            {
                $this->agora = new DateTimeImmutable(
                    '2026-08-20 17:00:00'
                );
            }

            public function substituirToken(
                int $usuarioId,
                string $tokenHash,
                DateTimeImmutable $expiraEm
            ): void {
                foreach ($this->registros as &$registro) {
                    if (
                        $registro['usuario_id'] === $usuarioId
                        && !$registro['usado']
                    ) {
                        $registro['usado'] = true;
                    }
                }
                unset($registro);

                $this->registros[$tokenHash] = [
                    'id' => $this->proximoId++,
                    'usuario_id' => $usuarioId,
                    'token_hash' => $tokenHash,
                    'expira_em' => $expiraEm,
                    'usado' => false,
                ];
            }

            public function buscarAtivoPorHash(
                string $tokenHash
            ): ?array {
                $registro = $this->registros[$tokenHash] ?? null;

                if (
                    $registro === null
                    || $registro['usado']
                    || $registro['expira_em'] <= $this->agora
                ) {
                    return null;
                }

                return [
                    'id' => $registro['id'],
                    'usuario_id' => $registro['usuario_id'],
                ];
            }

            public function redefinirSenhaPorHash(
                string $tokenHash,
                string $senhaHash
            ): ?int {
                $registro = $this->registros[$tokenHash] ?? null;

                if (
                    $registro === null
                    || $registro['usado']
                    || $registro['expira_em'] <= $this->agora
                ) {
                    return null;
                }

                $usuarioId = $registro['usuario_id'];
                $this->senhas[$usuarioId] = $senhaHash;

                foreach ($this->registros as &$item) {
                    if (
                        $item['usuario_id'] === $usuarioId
                        && !$item['usado']
                    ) {
                        $item['usado'] = true;
                    }
                }
                unset($item);

                return $usuarioId;
            }
        };

        $this->service = new PasswordResetService(
            $this->store,
            static fn (): DateTimeImmutable =>
                new DateTimeImmutable('2026-08-20 17:00:00')
        );
    }

    #[TestDox('Emite 256 bits em Base64URL e persiste somente SHA-256')]
    public function testEmiteTokenForteSemPersistirValorPuro(): void
    {
        $emitido = $this->service
            ->emitirParaUsuario(10);

        $token = $emitido['token'];

        self::assertMatchesRegularExpression(
            '/^[A-Za-z0-9_-]{43}$/',
            $token
        );

        self::assertSame(
            '2026-08-20 17:30:00',
            $emitido['expira_em']->format('Y-m-d H:i:s')
        );

        self::assertCount(1, $this->store->registros);

        $registro = array_values(
            $this->store->registros
        )[0];

        self::assertSame(64, strlen($registro['token_hash']));
        self::assertSame(hash('sha256', $token), $registro['token_hash']);
        self::assertNotSame($token, $registro['token_hash']);
    }

    #[TestDox('Nova emissão invalida token anterior do mesmo usuário')]
    public function testNovaEmissaoInvalidaTokenAnterior(): void
    {
        $primeiro = $this->service
            ->emitirParaUsuario(20)['token'];

        $segundo = $this->service
            ->emitirParaUsuario(20)['token'];

        self::assertNotSame($primeiro, $segundo);
        self::assertNull(
            $this->service->usuarioDoTokenValido($primeiro)
        );
        self::assertSame(
            20,
            $this->service->usuarioDoTokenValido($segundo)
        );
    }

    #[TestDox('Consulta token válido sem consumi-lo')]
    public function testConsultaNaoConsomeToken(): void
    {
        $token = $this->service
            ->emitirParaUsuario(30)['token'];

        self::assertSame(
            30,
            $this->service->usuarioDoTokenValido($token)
        );

        self::assertSame(
            30,
            $this->service->usuarioDoTokenValido($token)
        );
    }

    #[TestDox('Redefinição grava hash da nova senha e consome o token')]
    public function testRedefinicaoAlteraSenhaEConsomeToken(): void
    {
        $token = $this->service
            ->emitirParaUsuario(40)['token'];

        $usuarioId = $this->service->redefinirSenha(
            $token,
            'NovaSenha#2026',
            'NovaSenha#2026'
        );

        self::assertSame(40, $usuarioId);
        self::assertArrayHasKey(40, $this->store->senhas);
        self::assertNotSame(
            'NovaSenha#2026',
            $this->store->senhas[40]
        );
        self::assertTrue(
            password_verify(
                'NovaSenha#2026',
                $this->store->senhas[40]
            )
        );

        self::assertNull(
            $this->service->usuarioDoTokenValido($token)
        );
    }

    #[TestDox('Token já usado não consegue redefinir a senha novamente')]
    public function testRedefinicaoEhUsoUnico(): void
    {
        $token = $this->service
            ->emitirParaUsuario(50)['token'];

        self::assertSame(
            50,
            $this->service->redefinirSenha(
                $token,
                'PrimeiraSenha#2026',
                'PrimeiraSenha#2026'
            )
        );

        self::assertNull(
            $this->service->redefinirSenha(
                $token,
                'SegundaSenha#2026',
                'SegundaSenha#2026'
            )
        );

        self::assertTrue(
            password_verify(
                'PrimeiraSenha#2026',
                $this->store->senhas[50]
            )
        );

        self::assertFalse(
            password_verify(
                'SegundaSenha#2026',
                $this->store->senhas[50]
            )
        );
    }

    #[TestDox('Rejeita senha curta sem consumir o token')]
    public function testRejeitaSenhaCurtaSemConsumirToken(): void
    {
        $token = $this->service
            ->emitirParaUsuario(60)['token'];

        try {
            $this->service->redefinirSenha(
                $token,
                '1234567',
                '1234567'
            );

            self::fail('Era esperada senha curta inválida.');
        } catch (InvalidArgumentException $e) {
            self::assertSame(
                'A senha deve ter pelo menos 8 caracteres.',
                $e->getMessage()
            );
        }

        self::assertSame(
            60,
            $this->service->usuarioDoTokenValido($token)
        );
        self::assertArrayNotHasKey(60, $this->store->senhas);
    }

    #[TestDox('Rejeita confirmação divergente sem consumir o token')]
    public function testRejeitaConfirmacaoDivergenteSemConsumirToken(): void
    {
        $token = $this->service
            ->emitirParaUsuario(70)['token'];

        try {
            $this->service->redefinirSenha(
                $token,
                'NovaSenha#2026',
                'OutraSenha#2026'
            );

            self::fail('Era esperada confirmação inválida.');
        } catch (InvalidArgumentException $e) {
            self::assertSame(
                'A confirmação de senha não confere.',
                $e->getMessage()
            );
        }

        self::assertSame(
            70,
            $this->service->usuarioDoTokenValido($token)
        );
        self::assertArrayNotHasKey(70, $this->store->senhas);
    }

    #[TestDox('Rejeita token malformado sem tentar redefinir a senha')]
    public function testRejeitaTokenMalformado(): void
    {
        self::assertNull(
            $this->service->usuarioDoTokenValido('token-invalido')
        );

        self::assertNull(
            $this->service->redefinirSenha(
                'token-invalido',
                'NovaSenha#2026',
                'NovaSenha#2026'
            )
        );
    }

    #[TestDox('Rejeita usuário inválido na emissão')]
    public function testRejeitaUsuarioInvalido(): void
    {
        $this->expectException(\DomainException::class);
        $this->expectExceptionMessage(
            'Usuário inválido para recuperação de senha.'
        );

        $this->service->emitirParaUsuario(0);
    }
}
