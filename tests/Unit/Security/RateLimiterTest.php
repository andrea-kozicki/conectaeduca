<?php

declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Repository\RateLimitStore;
use ConectaEduca\Security\RateLimiter;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Limitação de requisições')]
final class RateLimiterTest extends TestCase
{
    protected function setUp(): void
    {
        $_SERVER['REMOTE_ADDR'] = '127.0.0.1';

        $store = new class implements RateLimitStore {
            private array $buckets = [];

            public function consume(
                string $acao,
                string $identificadorHash,
                int $limite,
                int $janelaSegundos
            ): bool {
                $key = $acao . '|' . $identificadorHash;

                $tentativas =
                    $this->buckets[$key] ?? 0;

                if ($tentativas >= $limite) {
                    return false;
                }

                $this->buckets[$key] =
                    $tentativas + 1;

                return true;
            }

            public function reset(
                string $acao,
                string $identificadorHash
            ): void {
                $key = $acao . '|' . $identificadorHash;

                unset($this->buckets[$key]);
            }
        };

        RateLimiter::setStore($store);
    }

    protected function tearDown(): void
    {
        RateLimiter::setStore(null);

        unset($_SERVER['REMOTE_ADDR']);
    }

    #[TestDox('Permite requisições dentro do limite')]
    public function testAllowPermitsRequestsInsideLimit(): void
    {
        $action =
            'login_test_' . bin2hex(random_bytes(4));

        $this->assertTrue(
            RateLimiter::allow($action, 2, 60)
        );

        $this->assertTrue(
            RateLimiter::allow($action, 2, 60)
        );
    }

    #[TestDox('Bloqueia requisições após exceder o limite')]
    public function testAllowBlocksAfterLimit(): void
    {
        $action =
            'login_test_' . bin2hex(random_bytes(4));

        $this->assertTrue(
            RateLimiter::allow($action, 2, 60)
        );

        $this->assertTrue(
            RateLimiter::allow($action, 2, 60)
        );

        $this->assertFalse(
            RateLimiter::allow($action, 2, 60)
        );
    }

    #[TestDox('Mantém buckets separados para ações diferentes')]
    public function testDifferentActionsHaveDifferentBuckets(): void
    {
        $this->assertTrue(
            RateLimiter::allow('acao_a', 1, 60)
        );

        $this->assertFalse(
            RateLimiter::allow('acao_a', 1, 60)
        );

        $this->assertTrue(
            RateLimiter::allow('acao_b', 1, 60)
        );
    }

    #[TestDox('Mantém buckets separados para identificadores diferentes')]
    public function testDifferentIdentifiersHaveDifferentBuckets(): void
    {
        $this->assertTrue(
            RateLimiter::allow(
                'login',
                1,
                60,
                'identificador-a'
            )
        );

        $this->assertFalse(
            RateLimiter::allow(
                'login',
                1,
                60,
                'identificador-a'
            )
        );

        $this->assertTrue(
            RateLimiter::allow(
                'login',
                1,
                60,
                'identificador-b'
            )
        );
    }

    #[TestDox('Permite resetar um bucket')]
    public function testResetAllowsRequestsAgain(): void
    {
        $identifier = 'conta-teste';

        $this->assertTrue(
            RateLimiter::allow(
                'login',
                1,
                60,
                $identifier
            )
        );

        $this->assertFalse(
            RateLimiter::allow(
                'login',
                1,
                60,
                $identifier
            )
        );

        RateLimiter::reset(
            'login',
            $identifier
        );

        $this->assertTrue(
            RateLimiter::allow(
                'login',
                1,
                60,
                $identifier
            )
        );
    }
}
