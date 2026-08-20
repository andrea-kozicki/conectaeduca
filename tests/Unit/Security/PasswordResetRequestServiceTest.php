<?php

declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Repository\PasswordResetStore;
use ConectaEduca\Service\PasswordResetRequestService;
use ConectaEduca\Service\PasswordResetService;
use DateTimeImmutable;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Solicitação segura de recuperação de senha')]
final class PasswordResetRequestServiceTest extends TestCase
{
    private PasswordResetStore $tokenStore;
    private PasswordResetService $tokenService;

    protected function setUp(): void
    {
        $this->tokenStore = new class implements PasswordResetStore {
            /** @var array<string,array{usuario_id:int,expira_em:DateTimeImmutable}> */
            public array $tokens = [];

            public function substituirToken(
                int $usuarioId,
                string $tokenHash,
                DateTimeImmutable $expiraEm
            ): void {
                foreach ($this->tokens as $hash => $registro) {
                    if ($registro['usuario_id'] === $usuarioId) {
                        unset($this->tokens[$hash]);
                    }
                }

                $this->tokens[$tokenHash] = [
                    'usuario_id' => $usuarioId,
                    'expira_em' => $expiraEm,
                ];
            }

            public function buscarAtivoPorHash(
                string $tokenHash
            ): ?array {
                $registro = $this->tokens[$tokenHash] ?? null;

                if ($registro === null) {
                    return null;
                }

                return [
                    'id' => 1,
                    'usuario_id' => $registro['usuario_id'],
                ];
            }

            public function redefinirSenhaPorHash(
                string $tokenHash,
                string $senhaHash
            ): ?int {
                return null;
            }
        };

        $this->tokenService = new PasswordResetService(
            $this->tokenStore,
            static fn (): DateTimeImmutable =>
                new DateTimeImmutable('2026-08-20 18:00:00')
        );
    }

    #[TestDox('Conta existente e inexistente recebem a mesma resposta pública')]
    public function testNaoEnumeraUsuariosPelaRespostaPublica(): void
    {
        $existente = $this->serviceForUser([
            'id' => 10,
            'nome' => 'Pessoa Teste',
            'email' => 'pessoa@exemplo.test',
            'conta_ativada' => 1,
        ])->solicitar(
            'pessoa@exemplo.test',
            '203.0.113.10'
        );

        $inexistente = $this->serviceForUser(null)
            ->solicitar(
                'ninguem@exemplo.test',
                '203.0.113.10'
            );

        self::assertSame('accepted', $existente['status']);
        self::assertSame('accepted', $inexistente['status']);
        self::assertSame(
            $existente['public_message'],
            $inexistente['public_message']
        );
        self::assertNotNull($existente['delivery']);
        self::assertNull($inexistente['delivery']);
    }

    #[TestDox('Conta ativa recebe token forte apenas na entrega interna')]
    public function testContaAtivaProduzEntregaInterna(): void
    {
        $resultado = $this->serviceForUser([
            'id' => 20,
            'nome' => 'Andrea Teste',
            'email' => 'andrea@exemplo.test',
            'conta_ativada' => 1,
        ])->solicitar(
            '  ANDREA@EXEMPLO.TEST  ',
            '198.51.100.20'
        );

        $delivery = $resultado['delivery'];

        self::assertIsArray($delivery);
        self::assertSame(20, $delivery['user_id']);
        self::assertSame('andrea@exemplo.test', $delivery['email']);
        self::assertSame('Andrea Teste', $delivery['name']);
        self::assertMatchesRegularExpression(
            '/^[A-Za-z0-9_-]{43}$/',
            $delivery['token']
        );
        self::assertSame(
            '2026-08-20 18:30:00',
            $delivery['expires_at']->format('Y-m-d H:i:s')
        );
        self::assertCount(1, $this->tokenStore->tokens);
        self::assertArrayHasKey(
            hash('sha256', $delivery['token']),
            $this->tokenStore->tokens
        );
    }

    #[TestDox('Conta inativa é tratada como não recuperável sem revelar o motivo')]
    public function testContaInativaNaoRecebeToken(): void
    {
        $resultado = $this->serviceForUser([
            'id' => 30,
            'nome' => 'Conta Inativa',
            'email' => 'inativa@exemplo.test',
            'conta_ativada' => 0,
        ])->solicitar(
            'inativa@exemplo.test',
            '192.0.2.30'
        );

        self::assertSame('accepted', $resultado['status']);
        self::assertNull($resultado['delivery']);
        self::assertCount(0, $this->tokenStore->tokens);
    }

    #[TestDox('Rate limit por IP bloqueia antes de consultar a conta')]
    public function testRateLimitIpBloqueiaAntesDaBusca(): void
    {
        $finderCalled = false;

        $service = new PasswordResetRequestService(
            $this->tokenService,
            static function (string $email) use (&$finderCalled): ?array {
                $finderCalled = true;
                return null;
            },
            static fn (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ): bool => $action !== 'password_reset_ip',
            static function (string $event, array $context): void {}
        );

        $resultado = $service->solicitar(
            'pessoa@exemplo.test',
            '203.0.113.40'
        );

        self::assertSame('rate_limited', $resultado['status']);
        self::assertNull($resultado['delivery']);
        self::assertFalse($finderCalled);
        self::assertCount(0, $this->tokenStore->tokens);
    }

    #[TestDox('Rate limit por conta e IP ocorre antes da descoberta da conta')]
    public function testRateLimitContaIpNaoDependeDaExistenciaDaConta(): void
    {
        $finderCalled = false;
        $actions = [];

        $service = new PasswordResetRequestService(
            $this->tokenService,
            static function (string $email) use (&$finderCalled): ?array {
                $finderCalled = true;
                return null;
            },
            static function (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ) use (&$actions): bool {
                $actions[] = $action;

                return $action !== 'password_reset_conta_ip';
            },
            static function (string $event, array $context): void {}
        );

        $resultado = $service->solicitar(
            'pessoa@exemplo.test',
            '203.0.113.50'
        );

        self::assertSame(
            ['password_reset_ip', 'password_reset_conta_ip'],
            $actions
        );
        self::assertSame('rate_limited', $resultado['status']);
        self::assertFalse($finderCalled);
        self::assertCount(0, $this->tokenStore->tokens);
    }

    #[TestDox('Identificador do bucket de conta usa hash do e-mail normalizado')]
    public function testBucketNaoCarregaEmailPuro(): void
    {
        $calls = [];

        $service = new PasswordResetRequestService(
            $this->tokenService,
            static fn (string $email): ?array => null,
            static function (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ) use (&$calls): bool {
                $calls[] = [
                    'action' => $action,
                    'limit' => $limit,
                    'window' => $window,
                    'identifier' => $identifier,
                ];

                return true;
            },
            static function (string $event, array $context): void {}
        );

        $service->solicitar(
            '  Pessoa@Exemplo.Test ',
            '198.51.100.60'
        );

        self::assertCount(2, $calls);
        self::assertSame('password_reset_ip', $calls[0]['action']);
        self::assertSame(20, $calls[0]['limit']);
        self::assertSame(900, $calls[0]['window']);
        self::assertSame('password_reset_conta_ip', $calls[1]['action']);
        self::assertSame(3, $calls[1]['limit']);
        self::assertSame(900, $calls[1]['window']);
        self::assertStringNotContainsString(
            'pessoa@exemplo.test',
            strtolower($calls[1]['identifier'])
        );
        self::assertStringContainsString(
            hash('sha256', 'pessoa@exemplo.test'),
            $calls[1]['identifier']
        );
    }

    #[TestDox('E-mail inválido é rejeitado após consumir apenas o bucket global de IP')]
    public function testEmailInvalidoNaoCriaBucketDeConta(): void
    {
        $actions = [];

        $service = new PasswordResetRequestService(
            $this->tokenService,
            static fn (string $email): ?array => null,
            static function (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ) use (&$actions): bool {
                $actions[] = $action;
                return true;
            },
            static function (string $event, array $context): void {}
        );

        try {
            $service->solicitar(
                'email-invalido',
                '192.0.2.70'
            );

            self::fail('Era esperado e-mail inválido.');
        } catch (InvalidArgumentException $e) {
            self::assertSame('E-mail inválido.', $e->getMessage());
        }

        self::assertSame(
            ['password_reset_ip'],
            $actions
        );
        self::assertCount(0, $this->tokenStore->tokens);
    }

    #[TestDox('Auditoria não recebe e-mail puro nem token de recuperação')]
    public function testAuditoriaNaoRecebeSegredosOuEmailPuro(): void
    {
        $audits = [];

        $service = new PasswordResetRequestService(
            $this->tokenService,
            static fn (string $email): ?array => [
                'id' => 80,
                'nome' => 'Pessoa Auditada',
                'email' => 'auditada@exemplo.test',
                'conta_ativada' => 1,
            ],
            static fn (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ): bool => true,
            static function (
                string $event,
                array $context
            ) use (&$audits): void {
                $audits[] = [
                    'event' => $event,
                    'context' => $context,
                ];
            }
        );

        $resultado = $service->solicitar(
            'auditada@exemplo.test',
            '203.0.113.80'
        );

        self::assertCount(1, $audits);
        self::assertSame(
            'password_reset_requested',
            $audits[0]['event']
        );
        self::assertSame(80, $audits[0]['context']['user_id']);
        self::assertSame(
            hash('sha256', 'auditada@exemplo.test'),
            $audits[0]['context']['email_hash']
        );

        $auditJson = json_encode($audits, JSON_THROW_ON_ERROR);

        self::assertStringNotContainsString(
            'auditada@exemplo.test',
            $auditJson
        );
        self::assertStringNotContainsString(
            $resultado['delivery']['token'],
            $auditJson
        );
    }

    private function serviceForUser(
        ?array $usuario
    ): PasswordResetRequestService {
        return new PasswordResetRequestService(
            $this->tokenService,
            static fn (string $email): ?array => $usuario,
            static fn (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ): bool => true,
            static function (string $event, array $context): void {}
        );
    }
}
