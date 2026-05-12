<?php
declare(strict_types=1);

namespace ConectaEduca\Security;

use ConectaEduca\Config\Env;
use RuntimeException;

final class CognitoJwtVerifier
{
    public static function verify(string $jwt): array
    {
        return self::verifyIdToken($jwt);
    }

    public static function verifyIdToken(string $jwt): array
    {
        $parts = explode('.', $jwt);

        if (count($parts) !== 3) {
            throw new RuntimeException('JWT inválido.');
        }

        [$encodedHeader, $encodedPayload, $encodedSignature] = $parts;

        $header = self::jsonDecode(self::base64UrlDecode($encodedHeader));
        $payload = self::jsonDecode(self::base64UrlDecode($encodedPayload));
        $signature = self::base64UrlDecode($encodedSignature);

        if (($header['alg'] ?? '') !== 'RS256') {
            throw new RuntimeException('Algoritmo JWT não permitido.');
        }

        $kid = $header['kid'] ?? null;

        if (!is_string($kid) || $kid === '') {
            throw new RuntimeException('JWT sem kid.');
        }

        $jwk = self::findJwkByKid($kid);
        $pem = self::jwkToPem($jwk);

        $data = $encodedHeader . '.' . $encodedPayload;

        $ok = openssl_verify($data, $signature, $pem, OPENSSL_ALGO_SHA256);

        if ($ok !== 1) {
            throw new RuntimeException('Assinatura JWT inválida.');
        }

        self::validateClaims($payload);

        return $payload;
    }

    private static function validateClaims(array $payload): void
    {
        $region = Env::required('COGNITO_REGION');
        $userPoolId = Env::required('COGNITO_USER_POOL_ID');
        $clientId = Env::required('COGNITO_CLIENT_ID');

        $expectedIssuer = "https://cognito-idp.{$region}.amazonaws.com/{$userPoolId}";

        if (($payload['iss'] ?? '') !== $expectedIssuer) {
            throw new RuntimeException('Issuer do token inválido.');
        }

        $now = time();

        if (isset($payload['exp']) && (int) $payload['exp'] < $now) {
            throw new RuntimeException('Token expirado.');
        }

        if (isset($payload['nbf']) && (int) $payload['nbf'] > $now) {
            throw new RuntimeException('Token ainda não é válido.');
        }

        $aud = $payload['aud'] ?? null;
        $tokenUse = $payload['token_use'] ?? null;

        if ($tokenUse !== null && $tokenUse !== 'id') {
            throw new RuntimeException('Token recebido não é id_token.');
        }

        if (is_string($aud) && $aud !== $clientId) {
            throw new RuntimeException('Audience do token inválida.');
        }

        if (is_array($aud) && !in_array($clientId, $aud, true)) {
            throw new RuntimeException('Audience do token inválida.');
        }

        if ($aud === null && isset($payload['client_id']) && $payload['client_id'] !== $clientId) {
            throw new RuntimeException('Client ID do token inválido.');
        }
    }

    private static function findJwkByKid(string $kid): array
    {
        $jwks = self::jwks();

        foreach ($jwks['keys'] ?? [] as $key) {
            if (($key['kid'] ?? '') === $kid) {
                return $key;
            }
        }

        throw new RuntimeException('Chave pública do JWT não encontrada no JWKS.');
    }

    private static function jwks(): array
    {
        $region = Env::required('COGNITO_REGION');
        $userPoolId = Env::required('COGNITO_USER_POOL_ID');

        $cacheFile = Env::rootPath('storage/cache/jwks.json');

        if (is_readable($cacheFile) && (time() - filemtime($cacheFile)) < 3600) {
            $cached = file_get_contents($cacheFile);

            if (is_string($cached) && $cached !== '') {
                $decoded = json_decode($cached, true);

                if (is_array($decoded) && isset($decoded['keys'])) {
                    return $decoded;
                }
            }
        }

        $url = "https://cognito-idp.{$region}.amazonaws.com/{$userPoolId}/.well-known/jwks.json";

        $json = file_get_contents($url);

        if ($json === false || trim($json) === '') {
            throw new RuntimeException('Não foi possível obter JWKS do Cognito.');
        }

        $jwks = json_decode($json, true);

        if (!is_array($jwks) || !isset($jwks['keys'])) {
            throw new RuntimeException('JWKS inválido.');
        }

        $cacheDir = dirname($cacheFile);

        if (!is_dir($cacheDir)) {
            mkdir($cacheDir, 0750, true);
        }

        file_put_contents($cacheFile, json_encode($jwks, JSON_UNESCAPED_SLASHES));

        return $jwks;
    }

    private static function jwkToPem(array $jwk): string
    {
        if (($jwk['kty'] ?? '') !== 'RSA') {
            throw new RuntimeException('JWK não é RSA.');
        }

        if (empty($jwk['n']) || empty($jwk['e'])) {
            throw new RuntimeException('JWK RSA incompleto.');
        }

        $modulus = self::base64UrlDecode((string) $jwk['n']);
        $exponent = self::base64UrlDecode((string) $jwk['e']);

        $modulus = self::asn1Integer($modulus);
        $exponent = self::asn1Integer($exponent);

        $rsaPublicKey = self::asn1Sequence($modulus . $exponent);

        $algorithmIdentifier = self::asn1Sequence(
            self::asn1ObjectIdentifier('1.2.840.113549.1.1.1') .
            self::asn1Null()
        );

        $subjectPublicKeyInfo = self::asn1Sequence(
            $algorithmIdentifier .
            self::asn1BitString($rsaPublicKey)
        );

        return "-----BEGIN PUBLIC KEY-----\n" .
            chunk_split(base64_encode($subjectPublicKeyInfo), 64, "\n") .
            "-----END PUBLIC KEY-----\n";
    }

    private static function jsonDecode(string $json): array
    {
        $decoded = json_decode($json, true);

        if (!is_array($decoded)) {
            throw new RuntimeException('JSON do JWT inválido.');
        }

        return $decoded;
    }

    private static function base64UrlDecode(string $data): string
    {
        $data .= str_repeat('=', (4 - strlen($data) % 4) % 4);
        $decoded = base64_decode(strtr($data, '-_', '+/'), true);

        if ($decoded === false) {
            throw new RuntimeException('Base64URL inválido.');
        }

        return $decoded;
    }

    private static function asn1Length(int $length): string
    {
        if ($length < 128) {
            return chr($length);
        }

        $temp = ltrim(pack('N', $length), "\x00");

        return chr(0x80 | strlen($temp)) . $temp;
    }

    private static function asn1Sequence(string $data): string
    {
        return "\x30" . self::asn1Length(strlen($data)) . $data;
    }

    private static function asn1Integer(string $data): string
    {
        if (ord($data[0]) > 0x7f) {
            $data = "\x00" . $data;
        }

        return "\x02" . self::asn1Length(strlen($data)) . $data;
    }

    private static function asn1BitString(string $data): string
    {
        return "\x03" . self::asn1Length(strlen($data) + 1) . "\x00" . $data;
    }

    private static function asn1Null(): string
    {
        return "\x05\x00";
    }

    private static function asn1ObjectIdentifier(string $oid): string
    {
        $parts = array_map('intval', explode('.', $oid));
        $first = (40 * $parts[0]) + $parts[1];

        $encoded = chr($first);

        foreach (array_slice($parts, 2) as $part) {
            $stack = [chr($part & 0x7f)];
            $part >>= 7;

            while ($part > 0) {
                array_unshift($stack, chr(($part & 0x7f) | 0x80));
                $part >>= 7;
            }

            $encoded .= implode('', $stack);
        }

        return "\x06" . self::asn1Length(strlen($encoded)) . $encoded;
    }
}