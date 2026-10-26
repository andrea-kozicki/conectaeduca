<?php
declare(strict_types=1);

namespace ConectaEduca\Tests\Unit\Security;

use ConectaEduca\Controller\InscricaoController;
use ConectaEduca\Controller\RelatorioController;
use ConectaEduca\Controller\AuditoriaController;
use ConectaEduca\Controller\OportunidadeController;
use ConectaEduca\Security\Authorization;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;
use ReflectionMethod;

/**
 * PA-05 / Pentest B preparacao: negativos por role, sem DB, VM ou HTTP.
 *
 * Verifica a semantica real de hasRole e a presença do guard no início do
 * handler por Reflection. Nao prova HTTP 401/403, ownership nem CSRF.
 */
#[TestDox('RBAC de candidatura e administracao - regressao offline')]
final class RbacCandidaturaNegativeTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
    }

    protected function tearDown(): void
    {
        $_SESSION = [];
    }

    /** @return iterable<string, array{string, string, bool}> */
    public static function roleCases(): iterable
    {
        foreach (['usuario', 'empresa', 'admin'] as $actor) {
            foreach (['usuario', 'empresa', 'admin'] as $required) {
                yield $actor . '_to_' . $required => [
                    $actor, $required, $actor === $required,
                ];
            }
        }
    }

    #[DataProvider('roleCases')]
    public function testRoleChecksAreExact(string $actor, string $required, bool $expected): void
    {
        $_SESSION['user'] = ['id' => 314, 'role' => $actor];
        self::assertSame($expected, Authorization::hasRole($required));
    }

    /** @return iterable<string, array{string}> */
    public static function deniedActors(): iterable
    {
        foreach (['empresa', 'admin', 'Empresa', 'administrador', '', 'usuario ', 'USUARIO'] as $actor) {
            yield $actor === '' ? 'empty_role' : $actor => [$actor];
        }
    }

    #[DataProvider('deniedActors')]
    public function testNonApplicantRolesNeverMatchApplicant(string $actor): void
    {
        $_SESSION['user'] = ['id' => 314, 'role' => $actor];
        self::assertFalse(Authorization::hasRole('usuario'));
    }

    public function testMissingRoleCannotBecomeApplicant(): void
    {
        $_SESSION['user'] = ['id' => 314];
        self::assertFalse(Authorization::hasRole('usuario'));
    }

    public function testNoSessionHasNoRole(): void
    {
        self::assertFalse(Authorization::hasRole('usuario'));
        self::assertFalse(Authorization::hasRole('empresa'));
        self::assertFalse(Authorization::hasRole('admin'));
    }

    /**
     * Extrai somente as linhas do metodo inspecionado, sem varrer para um guard
     * em outro handler. Exige autorização antes de qualquer uso de serviço.
     */
    private static function body(string $class, string $method): string
    {
        $reflection = new ReflectionMethod($class, $method);
        $path = $reflection->getFileName();
        self::assertIsString($path);
        $source = file($path, FILE_IGNORE_NEW_LINES);
        self::assertIsArray($source);
        return implode("\n", array_slice(
            $source,
            $reflection->getStartLine() - 1,
            $reflection->getEndLine() - $reflection->getStartLine() + 1
        ));
    }

    public function testApplicantEndpointsFailClosedByExplicitRoleGuard(): void
    {
        foreach (['minhas', 'criar', 'cancelar'] as $method) {
            $body = self::body(InscricaoController::class, $method);
            self::assertMatchesRegularExpression(
                sprintf('~^\\s*public function\\s+%s\\(\\): void\\s*\\{\\s*\\$user\\s*=\\s*Authorization::requireRole\\(\\x27usuario\\x27\\);~m', preg_quote($method, '~')),
                $body,
                "Candidatura {$method} nao exige perfil usuario imediatamente"
            );
            self::assertStringNotContainsString('Authorization::requireAuth()', $body);
        }
    }

    public function testEmployerEndpointsRequireEmpresaOrAdmin(): void
    {
        foreach (['recebidasEmpresa', 'atualizarStatusEmpresa', 'atualizarStatus'] as $method) {
            $body = self::body(InscricaoController::class, $method);
            self::assertMatchesRegularExpression(
                "~Authorization::requireAnyRole\\(\\['empresa', 'admin'\\]\\)~",
                $body,
                "Gestao de candidaturas deve exigir empresa/admin: {$method}"
            );
        }
        foreach (['gerenciarEmpresa', 'processarGestaoEmpresa', 'criar'] as $method) {
            $body = self::body(OportunidadeController::class, $method);
            self::assertMatchesRegularExpression(
                "~Authorization::requireAnyRole\\(\\['empresa', 'admin'\\]\\)~",
                $body
            );
        }
    }

    public function testAdminOnlyControllersRequireAdmin(): void
    {
        foreach (['index', 'json'] as $method) {
            self::assertMatchesRegularExpression(
                "~Authorization::requireRole\\('admin'\\)~",
                self::body(RelatorioController::class, $method)
            );
        }
        self::assertMatchesRegularExpression(
            '~Authorization::requireRole\\("admin"\\)~',
            self::body(AuditoriaController::class, 'index')
        );
    }
}
