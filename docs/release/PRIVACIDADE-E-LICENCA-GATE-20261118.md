# Gate de privacidade, autoria e distribuição do arquivo acadêmico

**Recorte:** 18/11/2026. Auditoria parcial de sete documentos públicos selecionados na `main`, sem varredura exaustiva de todas as branches, anexos, imagens, comentários ou histórico. Documento da prioridade 1 da [issue #249](https://github.com/andrea-kozicki/conectaeduca/issues/249). **Não autoriza tag, release ou publicação de novos anexos.**

## Constatações verificadas

- `composer.json` contém `"license": "proprietary"`, e não há `LICENSE` na raiz. `CITATION.cff` está presente com autoria e referência acadêmica, mas **citação não concede licença**. Preservar estado atual e solicitar decisão explícita sobre distribuição e direitos de componentes de terceiros/institucionais antes de publicar release.
- O workflow Gitleaks realiza checkout com histórico completo (`fetch-depth: 0`) e existe configuração `.gitleaks.toml` com allowlists pontuais. Aprovação do scanner **não equivale** a revisão de todos os campos, metadados e documentos institucionais.
- O `.gitignore` impede arquivos de evidência em geral, mas permite explicitamente `docs/evidencias/*.md` e `*.txt`. Isto é útil para textos sanitizados; arquivos *já versionados* não ficam protegidos retroativamente pelo `.gitignore`.
- Os sete documentos conferidos — `README.md`, `README.en.md`, `SECURITY.md`, `CITATION.cff`, `docs/portfolio/EVIDENCIAS-PUBLICAS.md`, `docs/encerramento/README.md` e `docs/release/RELEASE-ACADEMICO-CANDIDATO-2026-11-18.md` — **não apresentaram os padrões diretos** de PEM de chave privada, IP IPv4 RFC1918, endereço de e-mail ou caminho absoluto de HOME no snapshot examinado. Padrões são indicadores limitados, não prova de ausência de informação sensível.

## Gates bloqueados

| Gate | Estado | Aceite obrigatório |
| --- | --- | --- |
| `CE-PUB-CONTEXT` | PENDENTE | Revisão humana de contexto de README, PRs, comentários, relatórios, caminhos e imagens |
| `CE-PUB-INSTITUTIONAL` | PENDENTE | Avaliação de direitos institucionais, infraestrutura, metadados e eventual consentimento para divulgação |
| `CE-PUB-LICENSE` | PENDENTE | Decidir formalmente se mantém software proprietário/sem nova licença ou define outra política compatível com direitos |
| `CE-PUB-HISTORY` | PENDENTE | Avaliar conteúdo relevante no histórico, branches, anexos e possíveis identificadores, sem republicar valores |
| `CE-PUB-FREEZE` | PENDENTE | Após os merges autorizados, fixar SHA completo da `main` e os checks referentes ao mesmo corte |
| `CE-PUB-APPROVAL` | PENDENTE | Aprovar explicitamente a tag e os anexos do eventual release `source-only` |

O JSON `docs/operacao/CE-ACADEMIC-PUBLICATION-GATES-20261118.json` mantém status `BLOCKED_PENDING_APPROVAL`. Os testes offline verificam os principais invariantes e padrões **somente nos sete documentos declarados**. Não consultam VMs nem o GitHub remotamente. Os marcadores sintéticos dos testes não são credenciais.

**Regra de publicação:** não criar `LICENSE`, tag, GitHub Release ou anexar snapshots/dumps/screenshots privados por automação. Se surgir um segredo real, tratar remoção/rotação pelo canal responsável, sem colar seu valor em PRs, issues ou chats.
