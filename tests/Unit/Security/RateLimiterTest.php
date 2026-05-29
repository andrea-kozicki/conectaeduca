<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\RateLimiter;
use PHPUnit\Framework\TestCase;

final class RateLimiterTest extends TestCase
{
    protected function setUp(): void
    {
        $_SESSION = [];
        $_SERVER['REMOTE_ADDR'] = '127.0.0.1';
    }

    public function testAllowPermitsRequestsInsideLimit(): void
    {
        $action = 'login_test_' . bin2hex(random_bytes(4));

        $this->assertTrue(RateLimiter::allow($action, 2, 60));
        $this->assertTrue(RateLimiter::allow($action, 2, 60));
    }

    public function testAllowBlocksAfterLimit(): void
    {
        $action = 'login_test_' . bin2hex(random_bytes(4));

        $this->assertTrue(RateLimiter::allow($action, 2, 60));
        $this->assertTrue(RateLimiter::allow($action, 2, 60));
        $this->assertFalse(RateLimiter::allow($action, 2, 60));
    }

    public function testDifferentActionsHaveDifferentBuckets(): void
    {
        $this->assertTrue(RateLimiter::allow('acao_a', 1, 60));
        $this->assertFalse(RateLimiter::allow('acao_a', 1, 60));

        $this->assertTrue(RateLimiter::allow('acao_b', 1, 60));
    }
}
