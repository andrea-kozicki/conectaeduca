<?php

declare(strict_types=1);

namespace Tests\Unit\Security;

use ConectaEduca\Repository\MfaRecoveryStore;
use ConectaEduca\Service\MfaRecoveryService;
use PHPUnit\Framework\Attributes\TestDox;
use PHPUnit\Framework\TestCase;

#[TestDox('Códigos de recuperação do MFA')]
final class MfaRecoveryServiceTest extends TestCase
{
    private MfaRecoveryStore $store;
    private MfaRecoveryService $service;

    protected function setUp(): void
    {
        $this->store = new class implements MfaRecoveryStore {
            /** @var array<int, list<array{id:int,codigo_hash:string,usado:bool}>> */
            public array $registros = [];

            public function substituirCodigos(
                int $usuarioId,
                array $hashes
            ): void {
                $this->registros[$usuarioId] = [];

                foreach ($hashes as $indice => $hash) {
                    $this->registros[$usuarioId][] = [
                        'id' => $indice + 1,
                        'codigo_hash' => $hash,
                        'usado' => false,
                    ];
                }
            }

            public function buscarAtivos(
                int $usuarioId
            ): array {
                $resultado = [];

                foreach ($this->registros[$usuarioId] ?? [] as $registro) {
                    if ($registro['usado']) {
                        continue;
                    }

                    $resultado[] = [
                        'id' => $registro['id'],
                        'codigo_hash' => $registro['codigo_hash'],
                    ];
                }

                return $resultado;
            }

            public function marcarComoUsado(
                int $usuarioId,
                int $codigoId
            ): bool {
                foreach (
                    $this->registros[$usuarioId] ?? []
                    as $indice => $registro
                ) {
                    if (
                        $registro['id'] !== $codigoId
                        || $registro['usado']
                    ) {
                        continue;
                    }

                    $this->registros[$usuarioId][$indice]['usado'] = true;

                    return true;
                }

                return false;
            }

            public function quantidadeAtivos(
                int $usuarioId
            ): int {
                return count(
                    $this->buscarAtivos($usuarioId)
                );
            }
        };

        $this->service = new MfaRecoveryService(
            $this->store
        );
    }

    #[TestDox('Gera dez códigos únicos e persiste apenas hashes')]
    public function testGeraCodigosProtegidos(): void
    {
        $codigos = $this->service
            ->gerarParaUsuario(10);

        $this->assertCount(10, $codigos);
        $this->assertCount(
            10,
            array_unique($codigos)
        );

        foreach ($codigos as $codigo) {
            $this->assertMatchesRegularExpression(
                '/^[A-F0-9]{4}(?:-[A-F0-9]{4}){4}$/',
                $codigo
            );
        }

        $registros = $this->store->buscarAtivos(10);

        $this->assertCount(10, $registros);

        foreach ($registros as $registro) {
            $this->assertFalse(
                in_array(
                    $registro['codigo_hash'],
                    $codigos,
                    true
                )
            );

            $this->assertGreaterThanOrEqual(
                60,
                strlen($registro['codigo_hash'])
            );
        }
    }

    #[TestDox('Aceita um código válido uma única vez')]
    public function testCodigoValidoEhUsoUnico(): void
    {
        $codigo = 'AAAA-BBBB-CCCC-DDDD-EEEE';

        $this->registrarCodigo(
            20,
            $codigo
        );

        $this->assertTrue(
            $this->service->validarEConsumir(
                20,
                $codigo
            )
        );

        $this->assertFalse(
            $this->service->validarEConsumir(
                20,
                $codigo
            )
        );

        $this->assertSame(
            0,
            $this->service->quantidadeAtivos(20)
        );
    }

    #[TestDox('Aceita o código sem hífens e ignora diferenças de caixa')]
    public function testNormalizaFormatoDigitado(): void
    {
        $codigo = 'ABCD-1234-EF56-7890-ABCD';

        $this->registrarCodigo(
            30,
            $codigo
        );

        $digitado = strtolower(
            str_replace('-', '', $codigo)
        );

        $this->assertTrue(
            $this->service->validarEConsumir(
                30,
                $digitado
            )
        );
    }

    #[TestDox('Rejeita código inválido')]
    public function testRejeitaCodigoInvalido(): void
    {
        $this->registrarCodigo(
            40,
            '1111-2222-3333-4444-5555'
        );

        $this->assertFalse(
            $this->service->validarEConsumir(
                40,
                'CODIGO-INVALIDO'
            )
        );
    }

    #[TestDox('Não aceita código pertencente a outro usuário')]
    public function testCodigoNaoCruzaUsuarios(): void
    {
        $codigoUsuarioA =
            'AAAA-1111-BBBB-2222-CCCC';

        $this->registrarCodigo(
            50,
            $codigoUsuarioA
        );

        $this->registrarCodigo(
            51,
            'DDDD-3333-EEEE-4444-FFFF'
        );

        $this->assertFalse(
            $this->service->validarEConsumir(
                51,
                $codigoUsuarioA
            )
        );
    }

    private function registrarCodigo(
        int $usuarioId,
        string $codigo
    ): void {
        $normalizado = strtoupper(
            str_replace('-', '', $codigo)
        );

        $hash = password_hash(
            $normalizado,
            PASSWORD_DEFAULT
        );

        self::assertIsString($hash);

        $this->store->substituirCodigos(
            $usuarioId,
            [$hash]
        );
    }
}
