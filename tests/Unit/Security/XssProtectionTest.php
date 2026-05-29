<?php
declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Security\OutputEncoder;
use PHPUnit\Framework\TestCase;

final class XssProtectionTest extends TestCase
{
    public function testHtmlEncoderNeutralizesScriptTag(): void
    {
        $payload = '<script>alert(1)</script>';

        $encoded = OutputEncoder::html($payload);

        $this->assertStringContainsString('&lt;script&gt;', $encoded);
        $this->assertStringNotContainsString('<script>', $encoded);
    }

    public function testHtmlEncoderNeutralizesImageOnErrorPayload(): void
    {
        $payload = '<img src=x onerror=alert(1)>';

        $encoded = OutputEncoder::html($payload);

        $this->assertStringContainsString('&lt;img', $encoded);
        $this->assertStringNotContainsString('<img', $encoded);
        $this->assertStringNotContainsString('onerror=alert(1)>', $encoded);
    }

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
