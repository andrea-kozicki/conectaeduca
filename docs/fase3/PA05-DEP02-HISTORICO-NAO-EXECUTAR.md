# PA-05 — CE-PA05-DEP02: registro histórico, NÃO EXECUTAR

**Classificação:** evidência de change control de 08/11/2026, **não** procedimento de implantação atual. As correções de autorização da PR #229 e a idempotência da PR #251 foram revistas posteriormente; **não há homologação operacional destas alterações** nas VMs.

## Cadeia de custódia da proposta original

O script, o runbook e o workflow de sintaxe foram criados para uma fotografia **antiga** do PHP da EP125. Permanecem recuperáveis no histórico imutável do GitHub, não na árvore operacional atual:

| Artefato histórico | Referência imutável |
|---|---|
| Script original `ops/pa05/ce_pa05_dep02.py` | [commit 88581f8](https://github.com/andrea-kozicki/conectaeduca/blob/88581f8efb58b25cc8bb4788743c5276ac61824f/ops/pa05/ce_pa05_dep02.py), blob Git `7d84529076608587370323425701f41bd3f947cc` |
| Runbook original `ops/pa05/CE-PA05-DEP02-RUNBOOK.md` | [commit 88581f8](https://github.com/andrea-kozicki/conectaeduca/blob/88581f8efb58b25cc8bb4788743c5276ac61824f/ops/pa05/CE-PA05-DEP02-RUNBOOK.md), blob Git `192e29beec46627ea5867f9dd7cdbce743b5373a` |
| Validador estático legado `.github/workflows/pa05-deploy-static.yml` | [commit 88581f8](https://github.com/andrea-kozicki/conectaeduca/blob/88581f8efb58b25cc8bb4788743c5276ac61824f/.github/workflows/pa05-deploy-static.yml), blob Git `336688167408a061de2950d1e4ff249f7f2990eb` |

O instalador antigo aponta para o commit `10328ab6d67d59325c2ea3b707a5dce660c2bb8f`, com hashes dos **três arquivos PHP daquela versão**, imagem `conectaeduca/php-fpm:pa05-10328ab6` e imagem-base específica. O repositório `InscricaoRepository.php` **mudou novamente** na #251: reutilizar o script poderia instalar código anterior à correção de idempotência.

## Decisão de segurança

1. Retirar o script e o runbook da árvore `ops/pa05/`, impedindo que sejam tratados como rotina pronta de operação.
2. Retirar o workflow que validava somente os invariantes e a sintaxe daquele script legado: o seu êxito **não significava deploy aprovado**.
3. Manter a prova de origem pelos links e blobs imutáveis acima; não reescrever retroativamente os artefatos da fotografia de 08/11.
4. CI do PA-05 deve testar somente o **código atual** do branch da PR: PHP, MariaDB descartável, PHPUnit e SAST, inclusive em propostas à `main`.
5. Um futuro deploy exigirá **novo change ID, novo plano, verificação do runtime atual, imagens e hashes revalidados, rollback e aceite explícito**. Nenhum comando `--apply` do material histórico está autorizado.

**Limites das evidências:** CI não valida instalação, banco institucional, tráfego WAF, propriedade horizontal no runtime nem estado atual da EP125. Não inferir que o script histórico foi executado ou que a máquina mantém a imagem-base de 08/11. As VMs não foram acessadas por esta conciliação.

Relacionado: [PR #229](https://github.com/andrea-kozicki/conectaeduca/pull/229) e [PR #251](https://github.com/andrea-kozicki/conectaeduca/pull/251).
