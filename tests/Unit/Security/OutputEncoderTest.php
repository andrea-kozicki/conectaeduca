<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\OutputEncoder;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Codificação segura de saída')]
final class OutputEncoderTest extends TestCase
{
    #[TestDox('Escapa tag script em HTML')]
    public function testHtmlEscapesScriptTag(): void
    {
        $payload = '<script>alert("xss")</script>';

        $encoded = OutputEncoder::html($payload);

        $this->assertSame('&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;', $encoded);
        $this->assertStringNotContainsString('<script>', $encoded);
    }

    #[TestDox('Escapa aspas em atributo HTML')]
    public function testAttrEscapesQuotes(): void
    {
        $payload = '" onmouseover="alert(1)';

        $encoded = OutputEncoder::attr($payload);

        $this->assertStringContainsString('&quot;', $encoded);
        $this->assertStringNotContainsString('" onmouseover="', $encoded);
    }

    #[TestDox('Codifica caracteres inseguros em URL')]
    public function testUrlEncodesUnsafeCharacters(): void
    {
        $this->assertSame('a%20b%2Fc%3Fd%3D1', OutputEncoder::url('a b/c?d=1'));
    }

    #[TestDox('Usa flags HEX no JSON contra injeção HTML')]
    public function testJsonUsesHexOptionsAgainstHtmlInjection(): void
    {
        $json = OutputEncoder::json([
            'payload' => '<script>alert("xss")</script>',
        ]);

        $this->assertStringContainsString('\u003Cscript\u003E', $json);
        $this->assertStringNotContainsString('<script>', $json);
    }
}
