<?php

declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Repository\PasswordResetStore;
use ConectaEduca\Service\PasswordResetNotificationService;
use ConectaEduca\Service\PasswordResetRequestService;
use ConectaEduca\Service\PasswordResetService;
use DateTimeImmutable;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use RuntimeException;

#[TestDox('Entrega segura do e-mail de recuperação de senha')]
final class PasswordResetNotificationServiceTest extends TestCase
{
    private function requestServiceForUser(?array $user): PasswordResetRequestService
    {
        $store = new class implements PasswordResetStore {
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

            public function buscarAtivoPorHash(string $tokenHash): ?array
            {
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

        $tokens = new PasswordResetService(
            $store,
            static fn (): DateTimeImmutable =>
                new DateTimeImmutable('2026-08-20 18:30:00 UTC')
        );

        return new PasswordResetRequestService(
            $tokens,
            static fn (string $email): ?array => $user,
            static fn (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ): bool => true,
            static function (string $event, array $context): void {
            }
        );
    }

    #[TestDox('Conta recuperável recebe e-mail e a resposta pública não contém delivery nem token')]
    public function testSendsMailWithoutLeakingInternalDelivery(): void
    {
        $sent = [];
        $audits = [];

        $service = new PasswordResetNotificationService(
            $this->requestServiceForUser([
                'id' => 10,
                'nome' => 'Pessoa Teste',
                'email' => 'pessoa@exemplo.test',
                'conta_ativada' => 1,
            ]),
            static function (
                string $email,
                string $name,
                string $subject,
                string $html,
                string $text
            ) use (&$sent): void {
                $sent[] = compact(
                    'email',
                    'name',
                    'subject',
                    'html',
                    'text'
                );
            },
            static function (string $event, array $context) use (&$audits): void {
                $audits[] = compact('event', 'context');
            },
            static fn (string $token): string =>
                'https://conectaeduca.test/redefinir-senha.php#token=' . $token
        );

        $resultado = $service->solicitarEEnviar(
            'pessoa@exemplo.test',
            '203.0.113.10'
        );

        self::assertSame('accepted', $resultado['status']);
        self::assertArrayNotHasKey('delivery', $resultado);
        self::assertCount(1, $sent);
        self::assertSame('pessoa@exemplo.test', $sent[0]['email']);
        self::assertSame('Pessoa Teste', $sent[0]['name']);
        self::assertSame(
            'Recuperação de senha - ConectaEduca',
            $sent[0]['subject']
        );
        self::assertStringContainsString(
            '20/08/2026 às 16:00 (horário de Brasília)',
            $sent[0]['html']
        );
        self::assertStringContainsString(
            '20/08/2026 às 16:00 (horário de Brasília)',
            $sent[0]['text']
        );
        self::assertStringContainsString(
            'https://conectaeduca.test/redefinir-senha.php#token=',
            $sent[0]['html']
        );
        self::assertStringContainsString(
            'https://conectaeduca.test/redefinir-senha.php#token=',
            $sent[0]['text']
        );

        $publicJson = json_encode($resultado, JSON_THROW_ON_ERROR);
        self::assertStringNotContainsString('pessoa@exemplo.test', $publicJson);
        self::assertSame('password_reset_mail_sent', $audits[0]['event']);
        self::assertSame(['user_id' => 10], $audits[0]['context']);
    }

    #[TestDox('Conta inexistente mantém resposta genérica e não dispara e-mail')]
    public function testUnknownAccountDoesNotSendMail(): void
    {
        $sendCount = 0;

        $service = new PasswordResetNotificationService(
            $this->requestServiceForUser(null),
            static function () use (&$sendCount): void {
                $sendCount++;
            },
            static function (): void {
            },
            static fn (string $token): string =>
                'https://conectaeduca.test/redefinir-senha.php#token=' . $token
        );

        $resultado = $service->solicitarEEnviar(
            'ninguem@exemplo.test',
            '203.0.113.11'
        );

        self::assertSame('accepted', $resultado['status']);
        self::assertSame(0, $sendCount);
        self::assertArrayNotHasKey('delivery', $resultado);
    }

    #[TestDox('Falha SMTP não revela se a conta existe nem expõe o token na auditoria')]
    public function testMailFailureKeepsGenericPublicResponseAndSafeAudit(): void
    {
        $audits = [];
        $capturedToken = null;

        $service = new PasswordResetNotificationService(
            $this->requestServiceForUser([
                'id' => 20,
                'nome' => 'Pessoa Falha',
                'email' => 'falha@exemplo.test',
                'conta_ativada' => 1,
            ]),
            static function (): void {
                throw new RuntimeException('SMTP indisponível com detalhe secreto');
            },
            static function (string $event, array $context) use (&$audits): void {
                $audits[] = compact('event', 'context');
            },
            static function (string $token) use (&$capturedToken): string {
                $capturedToken = $token;

                return 'https://conectaeduca.test/redefinir-senha.php#token=' . $token;
            }
        );

        $resultado = $service->solicitarEEnviar(
            'falha@exemplo.test',
            '203.0.113.20'
        );

        self::assertSame('accepted', $resultado['status']);
        self::assertArrayNotHasKey('delivery', $resultado);
        self::assertNotNull($capturedToken);
        self::assertSame('password_reset_mail_failed', $audits[0]['event']);
        self::assertSame(['user_id' => 20], $audits[0]['context']);

        $auditJson = json_encode($audits, JSON_THROW_ON_ERROR);
        self::assertStringNotContainsString('falha@exemplo.test', $auditJson);
        self::assertStringNotContainsString((string) $capturedToken, $auditJson);
        self::assertStringNotContainsString('SMTP indisponível', $auditJson);
    }

    #[TestDox('Nome controlado pelo usuário é escapado no HTML do e-mail')]
    public function testEscapesUserNameInHtmlMail(): void
    {
        $html = '';

        $service = new PasswordResetNotificationService(
            $this->requestServiceForUser([
                'id' => 30,
                'nome' => '<script>alert(1)</script>',
                'email' => 'html@exemplo.test',
                'conta_ativada' => 1,
            ]),
            static function (
                string $email,
                string $name,
                string $subject,
                string $htmlBody,
                string $textBody
            ) use (&$html): void {
                $html = $htmlBody;
            },
            static function (): void {
            },
            static fn (string $token): string =>
                'https://conectaeduca.test/redefinir-senha.php#token=' . $token
        );

        $service->solicitarEEnviar(
            'html@exemplo.test',
            '203.0.113.30'
        );

        self::assertStringNotContainsString('<script>', $html);
        self::assertStringContainsString(
            '&lt;script&gt;alert(1)&lt;/script&gt;',
            $html
        );
    }

    #[TestDox('Rate limit não tenta construir link nem enviar e-mail')]
    public function testRateLimitedRequestDoesNotBuildOrSendMail(): void
    {
        $store = new class implements PasswordResetStore {
            public function substituirToken(
                int $usuarioId,
                string $tokenHash,
                DateTimeImmutable $expiraEm
            ): void {
                throw new RuntimeException('Token não deveria ser emitido sob rate limit.');
            }

            public function buscarAtivoPorHash(string $tokenHash): ?array
            {
                return null;
            }

            public function redefinirSenhaPorHash(
                string $tokenHash,
                string $senhaHash
            ): ?int {
                return null;
            }
        };

        $tokens = new PasswordResetService($store);

        $requests = new PasswordResetRequestService(
            $tokens,
            static fn (string $email): ?array => null,
            static fn (
                string $action,
                int $limit,
                int $window,
                string $identifier
            ): bool => false,
            static function (): void {
            }
        );

        $sendCount = 0;
        $buildCount = 0;

        $service = new PasswordResetNotificationService(
            $requests,
            static function () use (&$sendCount): void {
                $sendCount++;
            },
            static function (): void {
            },
            static function (string $token) use (&$buildCount): string {
                $buildCount++;

                return 'https://conectaeduca.test/redefinir-senha.php#token=' . $token;
            }
        );

        $resultado = $service->solicitarEEnviar(
            'limitado@exemplo.test',
            '203.0.113.40'
        );

        self::assertSame('rate_limited', $resultado['status']);
        self::assertSame(0, $sendCount);
        self::assertSame(0, $buildCount);
        self::assertArrayNotHasKey('delivery', $resultado);
    }
}
