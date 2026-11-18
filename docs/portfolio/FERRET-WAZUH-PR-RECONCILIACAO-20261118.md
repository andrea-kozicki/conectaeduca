# ConectaEduca — reconciliação GitHub Ferret/Wazuh (PA-07/PA-06)

**Corte técnico:** 18/11/2026; atualização de fonte após merge da #262. **Método:** comparação de arquivos, patches e metadados de PR no GitHub; **não** foram acessadas EP125/EP126, logs ou imagens institucionais. **Objetivo:** evitar a reintrodução de código e scripts históricos ao consolidar a `main`. Este documento não é autorização de deploy ou de publicação adicional de evidência privada.

## Constatações verificáveis no repositório

| Escopo | Evidência de código na `main` | Decisão de conciliação |
| --- | --- | --- |
| **PA-07 / regras Wazuh LOW, MEDIUM, HIGH — #206** | `deploy/interna/wazuh/config/rules/conectaeduca_dlp_rules.xml` já corresponde **byte a byte** ao da branch #206, blob Git `8d332c7adb8820789219c5c6e6b048eeecc178d2`. Regras 110111/110112/110113 são case-insensitive e regra 110101 exige contadores explícitos antes de silenciar um resumo sem achados | **Não integrar a PR #206 inteira**: repete regras já versionadas e contém documentação/CI de outro corte |
| **PA-07 / testes offline — #260** | [PR #260](https://github.com/andrea-kozicki/conectaeduca/pull/260) integrada à `main` com validador, suíte de contrato DLP sintética, workflow isolado e proveniência | Testes podem detectar regressão no **modelo offline**; não homologam PCRE2, `wazuh-logtest`, Manager ou E2E |
| **PA-07 / launcher Bash — #227 e #237** | `scripts/dlp/processar_inbox_ferret.sh` da #227 é byte a byte igual ao da `main` após a [#237](https://github.com/andrea-kozicki/conectaeduca/pull/237), blob `d980a038243876ad853b374d0e9895bc19e9e77e` | **Não integrar** novamente o Bash; a paridade de execução CLI versus Web v5 ainda carece de teste operacional |
| **PA-07 / launchers Fish e bootstrap — #227** | Os dois arquivos Fish da #227 **divergem** da `main`. A branch introduz seleção automática de imagem v5 por hostname/drop-in, caminho local de TAR e instalador fixado no checkout antigo | **Manter em draft**: extrair/refatorar só com avaliação da seleção explícita, portabilidade e testes Fish; não aplicar instalador com SHA antigo |
| **PA-07 / UI V4/V5 — #207 e #262** | A [#262](https://github.com/andrea-kozicki/conectaeduca/pull/262) integrou à `main` apenas os patches V4 e V5, suites JS e gate de fonte fixada (upstream `a5156d1950df19276e6cfd8335603d73187a3841`, blob `68192bc16891887240089e08634b5d41bf2588c1`): 20/20 testes V4, 26/26 V5 e 7/7 Actions PASS. A #207 preserva V3, Containerfile, imagem e demais artefatos **não** incorporados | **#207 continua DRAFT.** Fonte/testes não homologam navegador, binário Go, imagem em execução na EP126, HTTP 403 real nem rollback; não repetir/mesclar cutover histórico |
| **PA-07 / cutover histórico — #226** | Script e runbook têm pré-condições, imagem e checkout associados à fotografia de 08/11; o histórico relata implantação Web v5 e rollback preparado, não ensaiado | **Não reaplicar ou mesclar o instalador como rotina vigente**. Qualquer novo cutover exige baseline atualizado, janela, rollback e autorização institucional |
| **PA-06 / persistência audit PHP — #203** | O `compose.audit-persistent.yml` é idêntico ao da `main`, blob `bfb1abca81b0a5f84e8ccda69c3c2da75294f2a1`; `AuditLogger.php` e `AuditLoggerRedactionTest.php` também são idênticos à #203 | **Não reintegrar** essas correções já versionadas; outros artefatos da #203 (agente, regras e templates) dependem de verificação de rotas, retenção e privacidade |
| **PA-06 / Wazuh 80710 V6 — #240** | Regra V6 e validador de origem já reconciliados pela [#240](https://github.com/andrea-kozicki/conectaeduca/pull/240), com hash e documentação | A [#231](https://github.com/andrea-kozicki/conectaeduca/pull/231) foi substituída/encerrada; não relançar seu instalador antigo |
| **PA-06 / logrotate — #225** | PR operacional descreve instalação de política em 08/11 e limitações de giro/ingestão; código ainda em *draft* | **Não aplicar novamente**; distinguir configuração relatada de giro real, monitoramento após troca de inode e aprovação de retenção/PII |

## Fronteiras de evidência

1. **Código versionado não equivale à versão carregada** no Wazuh Manager, na CLI Ferret ou no contêiner Web da EP126.
2. Um arquivo com o mesmo Git blob comprova **igualdade dos bytes do arquivo comparado**, não identidade do runtime, imagem, estado de serviço ou proveniência do evento.
3. O script de #227 fixa usuário/host e commit de 08/11. O da #226 presume imagem e estado operacional daquela janela. **Não executar `--apply` ou repetir rollback com base apenas nesses commits.**
4. Os arquivos de #203 associados a coleta de auditoria e Wazuh dependem do caminho real do agente, método de entrega, política institucional de retenção e teste negativo de dados sensíveis. Importá-los como configuração ativa sem validação pode duplicar coleta ou alterar alertas.
5. Os relatórios de pentest registram observações e restrições; diferenças entre campanhas **não podem ser atribuídas exclusivamente ao Twingate**, e nenhum PA global é homologado por uma CI isolada.

## Encaminhamento sem VM

- Conservar as PRs #203, #206, #207, #226, #227 e #225 em *draft* até decisão individual; **não encerrar nem integrar em lote**.
- Utilizar os testes da #260 como regressão de regras DLP. A **extração source-only V4/V5 foi concluída pela #262**; CI validou aplicabilidade dos patches e 46 casos sintéticos, sem incorporar scripts de cutover ou fazer deploy. Reteste real da interface permanece pendente.
- Para o código Fish, exigir testes de sintaxe e regras explícitas de opt-in, evitando que um nome de host isolado ou caminho pessoal controle um novo deploy.
- Quando houver acesso institucional autorizado, registrar a fonte carregada, paridade de runtime e casos HTTP 403/inconclusivo com fixture sintética. Isso é gate posterior, **não objetivo desta conciliação de GitHub**.

**Resultado:** identificação de duplicidades confirmadas e lacunas de código/ensaio. Nenhuma alteração de WAF, Dockerfile, imagem, regra Wazuh ativa, VM, release ou permissões de acesso.
