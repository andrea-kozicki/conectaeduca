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

Antes de instalar, consultar `apt-cache policy bacula-fd` na versão Ubuntu da
VM e confirmar compatibilidade com o Director utilizado no laboratório. O
handoff não força downgrade/upgrade do Director apenas para igualar números de
versão.

## Aula / implantação

A preparação package-based pode ser demonstrada com
`scripts/implantacao/preparar_bacula_fd_ubuntu.sh`. No estado atual, porém, esse
script deve ser tratado como **bootstrap/preparação**, não como ativador final do
File Daemon.

Ele instala o pacote da distribuição e grava um candidato de configuração em
`/etc/bacula/bacula-fd.conf.conectaeduca`. O repositório ainda **não garante
fail-closed durante a instalação do pacote**, porque os maintainer scripts da
distribuição podem tentar iniciar o serviço padrão antes de a configuração
ConectaEduca, os segredos e o material TLS estarem prontos.

Por isso, o script atual não deve ser usado sozinho como gate de implantação em
uma VM limpa.

## Fonte de verdade do handoff

Para uma VM nova provisionada a partir deste repositório, o bootstrap atualmente
versionado é:

```text
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

Ele instala o pacote `bacula-fd` da distribuição e grava o template escolhido
em `/etc/bacula/bacula-fd.conf.conectaeduca`.

Esse bootstrap **ainda não constitui um caminho de ativação completo**. No estado
atual ele não:

- suprime de forma versionada o auto-start do pacote durante a instalação;
- promove o sidecar para a configuração consumida pelo serviço padrão;
- instala um override systemd que aponte explicitamente para o sidecar;
- valida o arquivo efetivo com `bacula-fd -t -c <arquivo>`;
- habilita/reinicia o daemon somente depois da materialização;
- comprova estado ativo e escuta final em TCP/9102.

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

1. o caminho package-based receber um procedimento versionado de ativação segura
   que, no mínimo:
   - impeça auto-start do `bacula-fd` durante a instalação inicial;
   - materialize segredo e certificados TLS fora do Git, com permissões mínimas;
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
