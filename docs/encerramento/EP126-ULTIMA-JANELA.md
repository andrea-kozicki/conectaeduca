# EP126 — última janela autorizada antes do desligamento

**Preparado em:** 18/11/2026, **sem acesso à VM**. Não significa que os passos
tenham sido executados. Deve ser usado somente enquanto a infraestrutura
estiver disponível e **com autorização para inventariar os arquivos**.

## Último inventário conhecido (17/11)

- A `main` local da EP126 estava em `04f88d275064a005d0ffcd4f9372a371c28c32d5`;
  a referência remota havia avançado para `4046ce2` naquela janela. Ambas são
  fotografias datadas; **não** representam a `main` remota atual.
- Sete arquivos V5 relacionados ao Ferret foram comparados byte a byte com a
  versão GitHub da época: o processador Bash e seis artefatos auxiliares
  apresentaram resultado `IDENTICO` (CE-GIT-EP126-16).
- Dois scripts Fish — `scripts/bootstrap/subir_ferret.fish` e
  `scripts/dlp/processar_inbox_ferret.fish` — mantinham alterações locais.
  **Fish é usado no openSUSE da autora**, não como shell operacional padrão da
  EP126 Ubuntu. Não integrar os diffs à `main` sem revisão específica.
- `RELEASE-METADATA.txt` existia localmente, não era versionado e apresentou
  marcadores que requerem classificação de privacidade. **Não publicar conteúdo,
  hash ou captura desse arquivo automaticamente.**
- O override Wazuh 80710 V6 foi observado no contêiner com SHA-256
  `4da3e4fe32a151f058c6d646340e8fc8a410e7bcfd41124207830cfc7e691ecf`;
  sua fonte já está versionada na PR #240. Essa confirmação é de 17/11,
  não de uma nova inspeção.
- O backup pré-reconciliação informou integridade `PASS` no CE-GIT-EP126-17,
  mas **uma cópia residente apenas na VM pode ser perdida no desligamento**.
  Não inferir custódia externa desse resultado.

## Procedimento mínimo — sem sudo e sem alteração de runtime

1. Confirmar a janela autorizada e a política de retenção/divulgação com o
   suporte. Priorizar arquivos e evidências **de autoria do projeto**.
2. Usar o script [manifesto EP126](../../scripts/evidencias/ep126_pre_encerramento_manifest.sh)
   em cópia ou worktree de revisão separada. **Não** fazer `git pull`,
   `reset`, `clean`, `stash`, `checkout` ou `merge` no diretório operacional.
3. Conferir apenas caminhos relativos, estado Git, tamanho, permissão e SHA-256
   dos nove arquivos conhecidos. O manifesto não lê o conteúdo em tela nem
   inclui o nome completo do host ou do usuário.
4. Comparar o manifesto com o GitHub *na mesma versão de referência*.
   Arquivos `IDENTICO` já versionados não exigem nova publicação.
5. Submeter os dois Fish a revisão de portabilidade e privacidade
   **separada**, sem presumir uso na EP126 nem alterar serviços existentes.
6. Tratar `RELEASE-METADATA.txt` apenas em espaço privado autorizado; caso
   contenha identificadores institucionais, descartar a divulgação pública.
7. Registrar na matriz final quais artefatos estão `PRESERVADO`,
   `NÃO PRESERVADO`, `RESTRITO` ou `NÃO VERIFICÁVEL`, com data e método.

Na EP126 (Bash), **depois de revisar o script** e dispondo de uma cópia de
revisão que o contenha:

```bash
bash -n scripts/evidencias/ep126_pre_encerramento_manifest.sh
bash scripts/evidencias/ep126_pre_encerramento_manifest.sh --repo /opt/conectaeduca
```

O script valida o papel do host e a raiz exata do checkout. Ele **não solicita
sudo, não executa Docker, não faz fetch, não cria pacote e não envia dados**.
O resultado não contém arquivos em texto claro, mas deve ser revisado antes
de qualquer compartilhamento público.

## Preservação e cadeia de custódia

| Classe | Conduta |
| --- | --- |
| Scripts autorais sem dados sensíveis | Revisar conteúdo e licença; integrar por PR se houver valor novo, registrando SHA anterior e posterior |
| Cópias já equivalentes ao GitHub | Registrar equivalência e não duplicar artefatos |
| Metadados institucionais, tokens, certificados, chaves e logs | **Não publicar**; manter sob a custódia apropriada ou descartar conforme orientação institucional |
| Backups, volumes, TARs e snapshots de hipervisor | Não exportar por iniciativa própria; depender de autorização específica e procedimento do responsável pela infraestrutura |
| Arquivo inacessível ou desaparecido | Marcar `NÃO VERIFICÁVEL` ou `NÃO PRESERVADO`; não inventar hash, teste ou restore |

## O que fica pendente mesmo após este manifesto

- Paridade integral entre EP126 e GitHub, caso diferenças não sejam
  reconciliadas e revisadas.
- Reteste operacional de Wazuh, Ferret, OpenBao, Bacula e acesso Twingate após
  a data do último inventário.
- Prova de restauração ponta a ponta do backup e de rollback real do Ferret V5.

O procedimento serve para **reduzir perda de informação**, não para declarar
o ambiente concluído ou alterar sua condição de segurança.
