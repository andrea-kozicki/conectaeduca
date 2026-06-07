<?php
declare(strict_types=1);

namespace ConectaEduca\Service;

use Aws\CognitoIdentityProvider\CognitoIdentityProviderClient;
use Aws\Exception\AwsException;
use ConectaEduca\Config\Env;
use RuntimeException;
use Throwable;

final class CognitoUserService
{
    private CognitoIdentityProviderClient $client;
    private string $userPoolId;

    public function __construct(?CognitoIdentityProviderClient $client = null)
    {
        $region = Env::required('COGNITO_REGION');
        $this->userPoolId = Env::required('COGNITO_USER_POOL_ID');

        $this->client = $client ?? new CognitoIdentityProviderClient([
            'version' => 'latest',
            'region' => $region,
            'credentials' => [
                'key' => Env::required('AWS_ACCESS_KEY_ID'),
                'secret' => Env::required('AWS_SECRET_ACCESS_KEY'),
            ],
        ]);
    }

    /**
     * Cria usuário no Cognito, define senha permanente, adiciona ao grupo e retorna o sub.
     *
     * @return array{username:string, sub:string, group:string}
     */
    public function criarUsuarioComSenhaPermanente(
        string $email,
        string $senha,
        string $nome,
        string $grupo
    ): array {
        $email = mb_strtolower(trim($email));
        $nome = trim($nome);
        $grupo = self::normalizarGrupo($grupo);
        $username = $email;
        $usuarioCriado = false;

        try {
            $this->client->adminCreateUser([
                'UserPoolId' => $this->userPoolId,
                'Username' => $username,
                'MessageAction' => 'SUPPRESS',
                'UserAttributes' => [
                    ['Name' => 'email', 'Value' => $email],
                    ['Name' => 'email_verified', 'Value' => 'true'],
                    ['Name' => 'name', 'Value' => $nome],
                ],
            ]);

            $usuarioCriado = true;

            $this->client->adminSetUserPassword([
                'UserPoolId' => $this->userPoolId,
                'Username' => $username,
                'Password' => $senha,
                'Permanent' => true,
            ]);

            $this->client->adminAddUserToGroup([
                'UserPoolId' => $this->userPoolId,
                'Username' => $username,
                'GroupName' => $grupo,
            ]);

            return [
                'username' => $username,
                'sub' => $this->obterSub($username),
                'group' => $grupo,
            ];
        } catch (AwsException $e) {
            if ($e->getAwsErrorCode() === 'UsernameExistsException') {
                throw new RuntimeException('Já existe uma conta no Cognito para este e-mail.', 0, $e);
            }

            if ($usuarioCriado) {
                $this->removerUsuarioSilenciosamente($username);
            }

            $message = $e->getAwsErrorMessage() ?: $e->getMessage();
            throw new RuntimeException('Falha ao provisionar usuário no Cognito: ' . $message, 0, $e);
        } catch (Throwable $e) {
            if ($usuarioCriado) {
                $this->removerUsuarioSilenciosamente($username);
            }

            throw $e;
        }
    }

    public function removerUsuario(string $username): void
    {
        $this->client->adminDeleteUser([
            'UserPoolId' => $this->userPoolId,
            'Username' => $username,
        ]);
    }

    private function removerUsuarioSilenciosamente(string $username): void
    {
        try {
            $this->removerUsuario($username);
        } catch (Throwable) {
            // Evita mascarar o erro principal. A falha será tratada em log externo, se necessário.
        }
    }

    private function obterSub(string $username): string
    {
        $result = $this->client->adminGetUser([
            'UserPoolId' => $this->userPoolId,
            'Username' => $username,
        ]);

        foreach ($result['UserAttributes'] ?? [] as $attribute) {
            if (($attribute['Name'] ?? '') === 'sub') {
                return (string) $attribute['Value'];
            }
        }

        throw new RuntimeException('Usuário criado no Cognito, mas o atributo sub não foi encontrado.');
    }

    public static function normalizarGrupoAutocadastro(string $grupo): string
    {
        return self::normalizarGrupo($grupo);
    }

    private static function normalizarGrupo(string $grupo): string
    {
        $grupo = strtolower(trim($grupo));

        if (!in_array($grupo, ['usuario', 'empresa'], true)) {
            throw new RuntimeException('Grupo Cognito inválido para autocadastro.');
        }

        return $grupo;
    }
}
