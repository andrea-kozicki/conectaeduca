# GA-07 / PA-06 — regras e coletor Wazuh candidatos, NÃO ativáveis

**Recorte 18/11/2026.** Materiais extraídos byte a byte da PR [#203](https://github.com/andrea-kozicki/conectaeduca/pull/203), mas gravados **somente em `docs/release/ga07-wazuh-candidates/` como `.candidate.txt`**. A extração não cria regras em `deploy/interna/wazuh/rules`, não altera `agent.conf`, não reinicia ou consulta Manager/Agente e não prova status de EP125/EP126.

## Conteúdo preservado e proveniência

- `rules.xml.candidate.txt`, Git blob da origem: `e22c1724fb42f6fb50ec9f9003314fd5000a8de0`. Registros candidatos 110250/110251/110252 para probe **sintético**, login falho e acesso não autorizado; níveis 3/5/7 do texto histórico.
- `localfile.xml.candidate.txt`, blob: `13326f2f421bbb3f3a12612b1c9251792da0028b`, fonte de um único coletor JSON proposto para `/var/log/conectaeduca/php-audit/audit.log`.
- `tests/python/test_ga07_wazuh_candidate_offline.py`: sete regressões em memória com XML, sintaxe dos campos e confronto contra IDs das regras *versionadas* em deploy. Não emite eventos, não abre logs nem acessa Docker.

## O que ainda NÃO foi validado

1. O Wazuh Manager real pode já ter regras com os mesmos IDs instaladas fora do GitHub: a comparação estática **não detecta** conflito em runtime.
2. O `agent.conf` versionado pode não coincidir com a configuração efetivamente carregada; um segundo `<localfile>` idêntico duplicaria coleta. Não aplicar sem inventário e comparação de agente/grupo.
3. `no_full_log` **não remove todos os campos decodificados** do alerta; privacidade, PII, retenção e autorização institucional permanecem pendentes.
4. A regex PCRE2, a cadeia de regras/decoder e os eventos de teste devem passar por ferramenta oficial do Wazuh e correlação agente → manager → dashboard em janela autorizada. Python `re` não é Wazuh `wazuh-logtest`.
5. A persistência do audit.log e a rotação em EP125 dependem de inventário real, permissões e aceite de dados. A PR #274 adicionou apenas testes de rotação sintética.

**Gate:** manter #203 em DRAFT e não instalar estes `.candidate.txt` como XML. Somente uma futura alteração específica, com ID livre, regras realmente carregadas, política de privacidade, rollback e testes E2E, poderá promover a configuração. As duas VMs permanecem intocadas.
