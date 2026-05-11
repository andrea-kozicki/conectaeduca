<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use InvalidArgumentException;

final class InputValidator
{
    public static function requiredString(?string $value, string $field, int $maxLength = 255): string
    {
        $value = trim((string) $value);

        if ($value === '') {
            throw new InvalidArgumentException("O campo {$field} é obrigatório.");
        }

        if (mb_strlen($value) > $maxLength) {
            throw new InvalidArgumentException("O campo {$field} excede {$maxLength} caracteres.");
        }

        return $value;
    }

    public static function optionalString(?string $value, int $maxLength = 255): ?string
    {
        $value = trim((string) $value);

        if ($value === '') {
            return null;
        }

        if (mb_strlen($value) > $maxLength) {
            throw new InvalidArgumentException("Campo excede {$maxLength} caracteres.");
        }

        return $value;
    }

    public static function email(?string $value): string
    {
        $value = trim((string) $value);

        if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
            throw new InvalidArgumentException('E-mail inválido.');
        }

        if (mb_strlen($value) > 180) {
            throw new InvalidArgumentException('E-mail excede o tamanho máximo permitido.');
        }

        return $value;
    }

    public static function id(mixed $value, string $field = 'id'): int
    {
        $id = filter_var($value, FILTER_VALIDATE_INT);

        if ($id === false || $id <= 0) {
            throw new InvalidArgumentException("Identificador inválido: {$field}.");
        }

        return $id;
    }

    public static function enum(?string $value, array $allowed, string $field): string
    {
        $value = trim((string) $value);

        if (!in_array($value, $allowed, true)) {
            throw new InvalidArgumentException("Valor inválido para {$field}.");
        }

        return $value;
    }

    public static function searchTerm(?string $value, int $maxLength = 100): string
    {
        $value = trim((string) $value);

        if (mb_strlen($value) > $maxLength) {
            throw new InvalidArgumentException('Termo de busca muito longo.');
        }

        return $value;
    }
}