<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

final class OutputEncoder
{
    public static function html(?string $value): string
    {
        return htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    public static function attr(?string $value): string
    {
        return htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    public static function url(?string $value): string
    {
        return rawurlencode($value ?? '');
    }

    public static function json(mixed $value): string
    {
        return json_encode(
            $value,
            JSON_HEX_TAG |
            JSON_HEX_AMP |
            JSON_HEX_APOS |
            JSON_HEX_QUOT |
            JSON_UNESCAPED_UNICODE |
            JSON_THROW_ON_ERROR
        );
    }
}