<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\RateLimiter;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Limitação de requisições')]
final class RateLimiterTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
        $_SERVER['REMOTE_ADDR'] = '127.0.0.1';
    }

    #[TestDox('Permite requisições dentro do limite')]
    public function testAllowPermitsRequestsInsideLimit(): void
    {
        $action = 'login_test_' . bin2hex(random_bytes(4));

        $this->assertTrue(RateLimiter::allow($action, 2, 60));
        $this->assertTrue(RateLimiter::allow($action, 2, 60));
    }

    #[TestDox('Bloqueia requisições após exceder o limite')]
    public function testAllowBlocksAfterLimit(): void
    {
        $action = 'login_test_' . bin2hex(random_bytes(4));

        $this->assertTrue(RateLimiter::allow($action, 2, 60));
        $this->assertTrue(RateLimiter::allow($action, 2, 60));
        $this->assertFalse(RateLimiter::allow($action, 2, 60));
    }

    #[TestDox('Mantém buckets separados para ações diferentes')]
    public function testDifferentActionsHaveDifferentBuckets(): void
    {
        $this->assertTrue(RateLimiter::allow('acao_a', 1, 60));
        $this->assertFalse(RateLimiter::allow('acao_a', 1, 60));

        $this->assertTrue(RateLimiter::allow('acao_b', 1, 60));
    }
}
