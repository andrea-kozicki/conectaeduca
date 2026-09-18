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

## Compatibilidade

O bootstrap versionado deriva automaticamente a versão esperada da imagem
`conectaeduca/bacula-director:X.Y.Z` declarada no Compose canônico e, depois de
`apt-get update`, consulta o candidato de `bacula-fd` com `LC_ALL=C apt-cache
policy`. A instalação é recusada antes de qualquer mudança de pacote quando o
candidato não corresponde à versão `X.Y.Z` do Director.

O handoff não força downgrade/upgrade do Director apenas para igualar números de
versão. A compatibilidade ainda deve ser confirmada live na VM final, mas um
candidato APT divergente agora falha fechado no próprio bootstrap.

## Aula / implantação

A preparação package-based pode ser demonstrada com
`scripts/implantacao/preparar_bacula_fd_ubuntu.sh`. No estado atual, porém, esse
script deve ser tratado como **bootstrap/preparação**, não como ativador final do
File Daemon.

Ele prepara o pacote e grava um candidato de configuração em
`/etc/bacula/bacula-fd.conf.conectaeduca`. A versão 2 do bootstrap adiciona os
seguintes gates antes/depois da instalação:

- deriva a versão esperada do Director versionado;
- atualiza o índice APT e recusa candidato `bacula-fd` incompatível;
- usa a política Debian `policy-rc.d` com retorno 101 para impedir auto-start
  durante a instalação; se já existir uma política local, ela é preservada e o
  bootstrap só prossegue quando comprova que também bloqueia o start;
- após a instalação, confirma a versão via `dpkg-query`;
- mantém `bacula-fd.service` parado, desabilitado e mascarado;
- grava o candidato como `root:bacula 0640`;
- não imprime segredo runtime e gera evidência com PASS/WARN/FAIL + SHA-256.

Esses controles tornam a **preparação do pacote** fail-closed no código
versionado, mas ainda não transformam o bootstrap em gate de implantação
completo. O fluxo precisa ser exercitado na VM e a ativação permanece separada.

## Fonte de verdade do handoff

Para uma VM nova provisionada a partir deste repositório, o bootstrap atualmente
versionado é:

```text
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

Ele instala o pacote `bacula-fd` da distribuição e grava o template escolhido
em `/etc/bacula/bacula-fd.conf.conectaeduca`.

Esse bootstrap **ainda não constitui um caminho de ativação completo**. A versão
2 já bloqueia o auto-start durante a instalação e mantém o serviço mascarado.
Quando o candidato não possui placeholders, também tenta
`bacula-fd -t -c /etc/bacula/bacula-fd.conf.conectaeduca`, sem ativar o daemon.

Ainda falta um reconciliador/gate de ativação que:

- materialize segredo e certificados TLS runtime;
- promova o sidecar para a configuração consumida pelo serviço padrão **ou**
  instale um override systemd explícito para o sidecar;
- rejeite placeholders/TLS ausente e valide o arquivo efetivo;
- desmascare, habilite/reinicie o daemon somente depois da validação;
- comprove estado ativo e escuta final em TCP/9102.

Logo, o handoff package-based deve permanecer classificado como **pendente de
ativação segura/reproduzível**, e não como rota de reconciliação já utilizável.

## Runtime observado nas VMs acadêmicas

A prova cross-zone de 14/09/2026 encontrou na EP125 um serviço pré-existente em:

```text
/opt/bacula/bin/bacula-fd
/opt/bacula/etc/bacula-fd.conf
```

Esse layout é específico do ambiente acadêmico observado e, no estado atual, não
há arquivo no repositório que explique como gerar essa instalação `/opt`.
Portanto:

- o runtime `/opt` pode ser usado como evidência do comportamento efetivamente
  testado na VM;
- ele **não deve ser descrito como reproduzível pelo handoff**;
- não se deve inventar um instalador `/opt` retrospectivamente sem conhecer a
  origem/procedimento real fornecido pela infraestrutura.

## Critério de reconciliação

O File Daemon só pode ser considerado simultaneamente **validado e reproduzível**
quando uma das condições abaixo for atendida:

1. o caminho package-based completar e validar o procedimento de ativação segura.
   O bootstrap v2 já impede auto-start e valida compatibilidade de versão; o gate
   restante deve, no mínimo:
   - materializar segredo e certificados TLS fora do Git, com permissões mínimas;
   - promova o candidato para a configuração efetivamente consumida pelo serviço
     **ou** instale um override systemd explícito para o arquivo candidato;
   - rejeite placeholders remanescentes e ausência dos arquivos TLS requeridos;
   - execute `bacula-fd -t -c <arquivo-efetivo>` antes de qualquer ativação;
   - somente após validação remova bloqueios temporários, habilite/reinicie o
     serviço e confirme estado ativo + TCP/9102;
   - seja exercitado em VM limpa e seguido pela repetição do fluxo cross-zone
     backup -> perda simulada -> restore -> SHA-256; ou
2. a infraestrutura/professor confirmar que `/opt/bacula` é o baseline
   institucional e o procedimento real de instalação/serviço for versionado e
   validado.

Até lá, a documentação deve distinguir explicitamente **validação funcional do
runtime acadêmico** de **reprodutibilidade do handoff**. Em particular, a opção
package-based permanece um **gate pendente**, não uma rota operacional já
fechada.

## Estado do pente fino de 18/09/2026

A versão 2 de `scripts/implantacao/preparar_bacula_fd_ubuntu.sh` foi preparada
por auditoria estática de repositório. Ela **não foi promovida a estado
operacional validado apenas por existir no Git**. O primeiro uso em EP125/EP126
deve anexar a evidência gerada pelo próprio bootstrap e confirmar que o
`policy-rc.d`, o pacote Bacula da origem APT efetiva e o mascaramento systemd
se comportaram como esperado antes de avançar para a ativação.
