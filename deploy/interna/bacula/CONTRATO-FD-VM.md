# ConectaEduca — contrato do Bacula File Daemon nas VMs

## Decisão

O File Daemon definitivo é **nativo no host Ubuntu**, não um container com bind
amplo do filesystem. O container `conectaeduca-bacula-filedaemon-lab` continua
sendo apenas ferramenta de laboratório/restore.

## VMs

- DMZ: `conectaeduca-dmz-fd`, TCP/9102.
- Interna: `conectaeduca-interna-fd`, TCP/9102.
- Director e Storage permanecem na VM interna.
- pfSense deve permitir 9102 somente entre Director e os File Daemons.

## Segurança

- TLS é obrigatório.
- Senhas e chaves são runtime e não entram no Git.
- Cada FD recebe segredo próprio.
- Certificados devem ser emitidos/materializados na implantação.
- Não copiar `.runtime` do host de desenvolvimento.
- O bootstrap de pacote é **prepare-only**: não substitui um FD já ativo e não
  promove automaticamente configuração efetiva.

## Compatibilidade e pacote de referência

A investigação live da EP125 em 18/09/2026 esclareceu a proveniência do layout
acadêmico `/opt/bacula`.

O runtime observado:

```text
/opt/bacula/bin/bacula-fd
/usr/lib/systemd/system/bacula-fd.service
/opt/bacula/etc/bacula-fd.conf
```

usa Bacula 15.0.3. O binário e a unit systemd pertencem ao pacote Debian
**`bacula-client`**, versão `15.0.3-1~noble`, fornecido pelo repositório
Bacula Community:

```text
https://www.bacula.org/packages/community/debs/15.0.3
```

O candidato APT do pacote Ubuntu `bacula-fd` é `13.0.4-1build3` e representa
uma rota de empacotamento diferente, incompatível com o Director 15.0.3 usado no
projeto. Portanto, `bacula-fd` **não é mais a fonte de verdade do bootstrap**.

O bootstrap versionado deriva a versão esperada da imagem
`conectaeduca/bacula-director:X.Y.Z` declarada no Compose canônico e exige:

1. candidato `bacula-client` com a mesma versão `X.Y.Z`;
2. origem comprovada no repositório Bacula Community da mesma versão;
3. simulação APT sem remoções;
4. bloqueio de auto-start por `policy-rc.d`;
5. serviço inativo ao final da preparação;
6. binário esperado em `/opt/bacula/bin/bacula-fd`.

A instalação é recusada antes da mudança de pacote quando esses gates não forem
satisfeitos.

## Aula / implantação

A preparação package-based é feita por:

```text
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

A versão 3 do bootstrap usa `bacula-client` e o layout `/opt/bacula`
comprovados na EP125.

Na Fase 2, o mesmo bootstrap também passou a resolver a raiz do projeto a
partir do próprio diretório do script (ou de `PROJECT_ROOT`, quando
explicitamente fornecido). Assim, o handoff extraído não depende de
`/srv/www/htdocs/conectaeduca` nem de checkout Git para localizar os templates.

O script:

- recusa execução sobre `bacula-fd.service` já ativo;
- executa `apt-get update`;
- valida candidato `bacula-client` e repositório Bacula Community;
- simula o plano APT e rejeita remoções;
- usa `policy-rc.d` com retorno 101 para bloquear auto-start;
- instala a versão exata do candidato;
- falha se observar auto-start mesmo assim;
- confirma a versão instalada via `dpkg-query`;
- mantém `bacula-fd.service` desabilitado e mascarado;
- preserva `/opt/bacula/etc/bacula-fd.conf` sem sobrescrevê-lo;
- grava apenas o candidato em
  `/opt/bacula/etc/bacula-fd.conf.conectaeduca`, `root:root 0600`;
- recusa sobrescrever candidato existente divergente;
- não imprime segredo runtime;
- gera evidência com PASS/WARN/FAIL e sidecar SHA-256.

O pacote `bacula-client` possui scripts de manutenção que podem tentar iniciar
o serviço durante a instalação. Por isso o `policy-rc.d` não é opcional no
bootstrap e a ausência de auto-start é verificada explicitamente após o APT.

## Fonte de verdade do handoff

Para VM nova, a fonte de verdade package-based passa a ser:

```text
pacote: bacula-client
versão: mesma X.Y.Z do Director
binário: /opt/bacula/bin/bacula-fd
unit: /usr/lib/systemd/system/bacula-fd.service
config efetiva: /opt/bacula/etc/bacula-fd.conf
candidato ConectaEduca: /opt/bacula/etc/bacula-fd.conf.conectaeduca
```

A configuração efetiva criada/gerenciada pelo pacote não é tratada como arquivo
do Git. O repositório fornece o candidato ConectaEduca e o procedimento de
reconciliação.

## Ativação continua separada

O bootstrap permanece **prepare-only**. Ele não materializa segredo ou
certificados TLS e não promove automaticamente o candidato para a configuração
efetiva.

O gate de ativação deve:

- materializar segredo e certificados TLS fora do Git, com permissões mínimas;
- rejeitar placeholders remanescentes;
- validar existência/legibilidade dos arquivos TLS;
- validar o candidato com
  `/opt/bacula/bin/bacula-fd -t -c <arquivo-candidato>`;
- promover de forma atômica o candidato para
  `/opt/bacula/etc/bacula-fd.conf` somente após validação;
- desmascarar/habilitar/reiniciar o daemon somente depois dos gates;
- confirmar estado ativo e TCP/9102;
- preservar rollback e evidência.

## Runtime acadêmico e reprodutibilidade

A antiga classificação de `/opt/bacula` como layout institucional sem
proveniência foi superada pela evidência de 18/09/2026.

Na EP125 foi comprovado que:

- `/opt/bacula/bin/bacula-fd` pertence a `bacula-client`;
- a unit `bacula-fd.service` pertence a `bacula-client`;
- `bacula-client 15.0.3-1~noble` está instalado;
- a mesma versão é o candidato APT;
- o candidato vem do repositório Bacula Community 15.0.3;
- o pacote Ubuntu `bacula-fd 13.0.4` não corresponde ao runtime validado.

Isso fecha a **proveniência package-based do layout /opt** sem reinstalar ou
interromper a EP125 live.

A validação funcional já realizada do runtime acadêmico — TCP/9102 e fluxo
cross-zone de backup/restore — permanece evidência de comportamento live e não
deve ser repetida apenas para provar a origem do pacote.

## Critério de fechamento do BAC-01

O BAC-01 pode ser considerado fechado quando:

1. a proveniência `bacula-client` 15.0.3 estiver documentada;
2. o bootstrap versionado refletir `bacula-client` e `/opt/bacula`;
3. os gates estáticos/CI do branch passarem;
4. ficar explícito que a ativação com segredo/TLS é gate separado e que o
   bootstrap não deve ser executado sobre a EP125 live já operacional.

Não é necessário reinstalar o pacote na EP125 para fechar a proveniência:
isso introduziria risco sem acrescentar evidência relevante.

## Estado do pente fino de 18/09/2026

A versão 3 de `scripts/implantacao/preparar_bacula_fd_ubuntu.sh` substitui a
hipótese anterior baseada no pacote Ubuntu `bacula-fd`.

O runtime live da EP125 permanece inalterado. A correção é repo-only e deve
passar pelos checks do PR #91 antes de ser propagada pela stack #92 → #94.
