# Pente fino estático do repositório — 18/09/2026

## Escopo

Auditoria executada sem acesso às VMs EP125/EP126. O objetivo é separar:

1. problemas resolvíveis integralmente no Git;
2. melhorias que podem ser preparadas no Git, mas exigem validação posterior na VM;
3. gates que dependem necessariamente do runtime acadêmico.

A auditoria não substitui validação live de rede, serviços, firewall, backup/restore
ou autenticação contra os componentes em execução.

## Estado encontrado

No início da auditoria o repositório possuía, aproximadamente:

- 516 arquivos rastreados;
- 101 scripts Shell/Python relevantes;
- 33 arquivos Compose;
- 108 documentos Markdown;
- quatro workflows de CI no branch operacional em revisão.

O único arquivo rastreado com tamanho zero era:

`docs/evidencias/composer-audit-final.txt`

Ele foi removido neste branch. Uma evidência vazia não demonstra execução nem
resultado e não deve ser preservada com o rótulo "final".

## Correções repo-only

### Gate geral de integridade estática

Foi criado `.github/workflows/repository-static-integrity.yml`, com:

- runner fixo `ubuntu-24.04`;
- `actions/checkout` fixado por SHA e sem persistência de credencial;
- `bash -n`/ `sh -n` para scripts Shell rastreados;
- parsing AST de todos os Python;
- rejeição de definições top-level Python duplicadas;
- rejeição de múltiplos guards `if __name__ == "__main__"`;
- validação de JSON rastreado;
- rejeição de arquivos vazios, exceto `.gitkeep`;
- rejeição de padrões de shell root persistente (`sudo -s`, `sudo -i`,
  `sudo su`);
- rejeição de `chmod 777/0777`;
- rejeição de download diretamente encadeado para `sh/bash`;
- rejeição de Actions externas sem pin SHA de 40 caracteres;
- rejeição de `ubuntu-latest` nos workflows do projeto;
- rejeição de marcadores de conflito de merge.

O objetivo é transformar falhas recorrentes de integridade de scripts em erro de
CI antes de chegarem à VM.

### Bootstrap do Bacula File Daemon

`scripts/implantacao/preparar_bacula_fd_ubuntu.sh` foi endurecido como preparação
fail-closed:

- deriva a versão esperada do Director versionado;
- consulta o candidato APT com locale controlado;
- recusa versão divergente antes da instalação;
- impede auto-start durante a instalação por `policy-rc.d`;
- preserva uma política local existente e só prossegue quando ela também nega start;
- confirma a versão instalada via `dpkg-query`;
- mantém `bacula-fd.service` parado, desabilitado e mascarado;
- grava o candidato de configuração como `root:root 0600`;
- gera evidência PASS/WARN/FAIL + SHA-256;
- não ativa o serviço.

Isso fecha somente o bootstrap. TLS, segredo runtime, promoção da configuração,
desmascaramento/ativação e validação TCP/9102 continuam como gate de VM.

## Reprodutibilidade Wazuh encontrada no pente fino

A auditoria encontrou um drift entre a evidência operacional e o Git:
`docs/evidencias/wazuh-dashboard-acl-reprodutivel-20260907.md` registra um
watcher `systemd.path` funcional na EP126 para reaplicar a ACL mínima do
`wazuh.yml`, mas o checkpoint histórico apontava para
`scripts/implantacao/instalar_wazuh_dashboard_acl.sh`, arquivo inexistente no
repositório.

Foi criado
`scripts/implantacao/reconciliar_wazuh_dashboard_acl.sh` como novo
reconciliador versionado, sem alegar reconstrução byte-a-byte do artefato
histórico. O contrato preservado é:

- `wazuh.yml` sem acesso de group/other;
- única named-user ACL `UID 1000 = r--`;
- helper root-owned + `systemd.path` + oneshot;
- CHECK, APPLY explícito, self-test, backup e rollback da ACL anterior;
- evidência PASS/WARN/FAIL + SHA-256.

O checkpoint legado foi reconciliado para apontar ao artefato que realmente
existe.

Também foi identificado que o handoff interno não transportava os
reconciliadores de PKI/identidade Wazuh incorporados pela PR #87. O gerador e o
verificador do handoff agora incluem/exigem:

- `reconciliar_wazuh_api_pki.py`;
- `reconciliar_wazuh_teste_readonly.py`;
- `reconciliar_wazuh_dashboard_acl.sh`;
- `validar_wazuh_operacional.sh`.

O novo reconciliador de ACL permanece **PREPARADO NO GIT / VALIDAR NA EP126**;
nenhum estado live foi inferido a partir da alteração do repositório.

## Correção incorporada ao PR #89

O workflow `.github/workflows/infra-script-tests.yml` do PR #89 foi endurecido
separadamente para:

- `ubuntu-24.04`;
- checkout por SHA;
- `persist-credentials: false`;
- timeout explícito.

Essa alteração permanece no PR #89 e não é duplicada neste branch.

## Gates que continuam exigindo host

Os seguintes itens não devem ser marcados como concluídos por auditoria estática:

- restricted Console Bacula `teste` e E2E de ACL;
- ativação segura/reproduzível do Bacula FD nativo;
- escuta TCP/9102 e fluxo Director -> FD;
- decoder/regra/archive/alert/indexação pfSense -> Wazuh;
- validações de regras pfSense e Suricata live;
- backup/perda simulada/restore/SHA-256;
- qualquer reconciliação que dependa do volume/configuração runtime protegido.

## Próximas frentes repo-only

Após o gate estático ficar verde, a próxima rodada deve priorizar:

1. referências documentais para arquivos/caminhos que não existem mais;
2. divergência entre `compose.yml`, `compose.vm.yml` e overlays do handoff;
3. scripts de implantação que ainda fazem instalação/mutação sem preflight;
4. documentação histórica na raiz que possa ser movida para seção de legado;
5. cobertura CI para arquivos de configuração que possam ser validados sem
   material runtime.

Qualquer correção adicional deve continuar distinguindo "código preparado" de
"estado operacional comprovado".