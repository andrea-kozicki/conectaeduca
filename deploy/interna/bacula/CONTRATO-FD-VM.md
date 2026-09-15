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

A instalação nativa pode ser demonstrada com
`scripts/implantacao/preparar_bacula_fd_ubuntu.sh`. O script instala o pacote,
copia o template escolhido e **não inicia o daemon enquanto placeholders de
segredo estiverem presentes**.


## Fonte de verdade do handoff

Para uma VM nova provisionada a partir deste repositório, a fonte de verdade é o
instalador:

```text
scripts/implantacao/preparar_bacula_fd_ubuntu.sh
```

Ele instala o pacote `bacula-fd` da distribuição e grava o template escolhido
em `/etc/bacula/bacula-fd.conf.conectaeduca`. O serviço permanece fail-closed
enquanto placeholders de segredo/TLS não forem materializados.

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

1. uma VM limpa for provisionada com
   `scripts/implantacao/preparar_bacula_fd_ubuntu.sh`, os materiais runtime
   forem materializados e o fluxo cross-zone completo for repetido; ou
2. a infraestrutura/professor confirmar que `/opt/bacula` é o baseline
   institucional e o procedimento real de instalação/serviço for versionado e
   validado.

Até lá, a documentação deve distinguir explicitamente **validação funcional do
runtime acadêmico** de **reprodutibilidade do handoff**.
