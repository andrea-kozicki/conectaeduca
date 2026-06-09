<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\OutputEncoder;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Proteção contra XSS')]
final class XssProtectionTest extends TestCase
{
    #[TestDox('Neutraliza tag script no encoder HTML')]
    public function testHtmlEncoderNeutralizesScriptTag(): void
    {
        $payload = '<script>alert(1)</script>';

        $encoded = OutputEncoder::html($payload);

        $this->assertStringContainsString('&lt;script&gt;', $encoded);
        $this->assertStringNotContainsString('<script>', $encoded);
    }

    #[TestDox('Neutraliza payload de imagem com onerror')]
    public function testHtmlEncoderNeutralizesImageOnErrorPayload(): void
    {
        $payload = '<img src=x onerror=alert(1)>';

        $encoded = OutputEncoder::html($payload);

        $this->assertStringContainsString('&lt;img', $encoded);
        $this->assertStringNotContainsString('<img', $encoded);
        $this->assertStringNotContainsString('onerror=alert(1)>', $encoded);
    }

    #[TestDox('Escapa caracteres sensíveis de HTML no encoder JSON')]
    public function testJsonEncoderHexEscapesHtmlSensitiveCharacters(): void
    {
        $payload = [
            'html' => '<img src=x onerror=alert(1)>',
        ];

        $json = OutputEncoder::json($payload);

        $this->assertStringContainsString('\u003Cimg', $json);
        $this->assertStringNotContainsString('<img', $json);
    }
}
