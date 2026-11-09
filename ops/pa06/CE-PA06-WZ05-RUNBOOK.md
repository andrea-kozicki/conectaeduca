# CE-PA06-WZ05 — Remediar regra 80710 na EP126

**VM:** EP126 `ep126-pucpr-br` (192.168.6.50), Wazuh Manager Docker 4.14.7.
**Data:** 08/11/2026. **Operadora:** Andréa Kozicki.
**Mudança:** PA-06-OBS-02 (falso positivo de modo promíscuo).
**Status:** preparado em GitHub PR #231 DRAFT, **não aplicado na VM**.

## Evidência e diagnóstico

- WZ01 20:47: Wazuh Manager, Indexer, Dashboard healthy; logtest disponível; regra local existente.
- WZ02 20:50: regra 80710 original level 10 em `/var/ossec/ruleset/rules/0365-auditd_rules.xml`, `if_sid=80700`, `audit.type=ANOM_PROMISCUOUS`, `match=prom=256`; sem override; `/var/ossec/etc` em volume persistente.
- WZ03 20:57: falso inconclusivo porque parser consultava stdout. WZ04 21:00: `wazuh-logtest -v` escreve fases em **stderr**; auditoria sintética ativação `prom=256 old_prom=0` detectou decoder auditd e rule ID **80710**. Teste desativação ainda não realizado no WZ04.
- WZ05 agora reproduz o falso positivo no `--preflight`, sem qualquer gravação. Só aplica se a **desativação 256→0 também disparar 80710**, demonstrando risco real na instância ativa.

## Correção proposta

Arquivo exclusivo no volume persistente do Manager: `/var/ossec/etc/rules/ce_pa06_80710_promisc.xml`. **Não altera** arquivos de fábrica, `ossec.conf`, regras 110xxx, índices ou agentes.

Usa `overwrite="yes"` na própria rule ID 80710, preservando nível 10, `if_sid=80700`, `audit.type=ANOM_PROMISCUOUS`, descrição e grupos de compliance, mas substitui o critério textual `prom=256` por **conjunção** de campos decodificados:
```xml
<field name="audit.prom" type="pcre2">^256$</field>
<field name="audit.old_prom" type="pcre2">^0$</field>
```
Wazuh recomenda `overwrite="yes"` em `/var/ossec/etc/rules`, e múltiplos `field` em uma regra são combinados por AND:
- https://documentation.wazuh.com/current/user-manual/ruleset/rules/custom.html
- https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/rules.html

Isso **mantém** o alerta level 10 na transição 0→256, sem classificar como ativação a desativação 256→0 ou a manutenção 256→256. Não reduz nível e não cria supressão ampla de auditd.

## Procedimento e guardas

**Somente leitura:** `python3 ce_pa06_wz05.py --preflight`. Requer conta `andrea.kiew`, hostname EP126, 3 serviços Wazuh healthy, imagem Manager 4.14.7, volume `/var/ossec/etc` persistente e sem override 80710. Lê regra de fábrica e arquivo local e usa `wazuh-logtest -v` com stderr+stdout para validar campos `audit.prom`, `audit.old_prom` e ID da regra nos casos: 0→256, 256→0, 256→256. Se desativação não gerar 80710, aborta antes de qualquer mudança.

**Instalação autorizada e exclusiva:** `python3 ce_pa06_wz05.py --apply`. Repete preflight; cria evidência privada em `~/.local/share/conectaeduca/pa06/WZ05-YYYYMMDD-HHMMSS`; arquivo XML próprio e SHA256. Faz `docker cp` apenas do novo arquivo para o Manager (volume do etc), `chmod 0644`, verifica hash, exige três casos no `wazuh-logtest` no estado **pré-restart**. Se regra não compilar ou não bloquear falso positivo, tenta excluir somente seu arquivo (não reinicia o serviço nesse caso).

**Ativação:** após PASS de 3 casos, usa `docker restart --time 20 conectaeduca-wazuh-wazuh.manager-1` **somente Manager**, aguarda health até ~130 s e confirma outros dois componentes Wazuh saudáveis. Executa de novo três testes de regra após reinício. Se falhar, rollback **best effort** exclui apenas novo arquivo e reinicia Manager. **Risco residual:** o restart cria possível janela breve de indisponibilidade de ingestão, e rollback pode exigir intervenção manual se o contêiner ficar parado ou sem `docker exec`. Recomendado snapshot institucional da EP126 após Ferret v5 de 08/11, mas não declarar snapshot disponível se não comprovado.

Não executar `docker compose down`, `systemctl restart` de host, `docker volume rm`, `docker prune`, `rm -rf`, root shell ou `sudo -s`. Não colar logs completos de Wazuh.

## Provas esperadas e limites

- `CE-PA06-WZ05_PREFLIGHT_PASS`: **somente leitura**, bug de desativação reproduzido por logtest.
- `CE-PA06-WZ05_IMPLANTADO`: override em volume persistente + 3 regressões em sandbox logtest + Manager healthy após reinício. **Ainda não comprova** alerta de produção real/indexação e redução quantitativa de ruído. Para isso, verificar contagem antes/depois em janela comparável e monitorar agentes.
- `ROLLBACK_ESTADO=INCOMPLETO`: interromper imediatamente, não reaplicar, preservar contexto e consultar suporte para restauração.

**Governança:** PA-06 fica parcial até confirmação de mudança real, continuidade de telemetria do Agent e ausência de supressão indevida. A PR fica DRAFT, não avançar main/checkout só para executar script versionado por commit imutável.


## WZ05 V3 21:34 — compatibilidade com regras locais em fragmentos (08/11/2026)

**Resultado EP126 de `andrea.kiew`, 21:34:58 -03:00:**
```text
SCRIPT_WZ05_V3_VALIDADO
IMAGEM_MANAGER_PIN_SHA256=CONFIRMADO
WAZUH_3_SERVICOS=HEALTHY
REGRA80710_ORIGINAL=CONFIRMADA
CE-PA06-WZ05_ABORTADO=REGRA_LOCAL_XML_INVALIDO
```

**Interpretação:** a guarda de imagem fixada pelo digest observado no WZ06 passou; os três contêineres Wazuh estão saudáveis e a regra 80710 de fábrica foi lida corretamente. O aborto ocorreu em `no_previous_override()` ao tentar interpretar, um a um, os nove XML locais por `xml.etree.ElementTree.fromstring`; **este parser exige uma única raiz**, enquanto a sintaxe de arquivos de regras do Wazuh pode conter vários blocos `<group>` de nível superior. Sem a identificação privada do arquivo específico, **não afirmar que determinado XML estava inválido ou comprovadamente tinha múltiplas raízes**. Não houve `--apply`, `docker cp`, restart ou alteração de regra.

**Correção versionada:** substituir a validação estrutural genérica e desnecessária sobre todos os arquivos por uma guarda **fail-closed sobre a ocorrência literal do ID 80710 em cada XML local**. Qualquer ocorrência (inclusive comentários/regex) resulta em `REGRA80710_JA_REFERENCIADA_EM_XML_LOCAL` e nenhum arquivo é alterado. Os demais erros de leitura continuam abortando por falha Docker. Conserva a checagem `test ! -e` do caminho de override e todas as demais pré-condições. O Wazuh logtest continua sendo o teste efetivo de compilação/semântica das regras; não interpretar o resultado como uma auditoria XML geral.

CI da correção contempla (a) fragmento sintético com dois `<group>` sem 80710 aceito; (b) referência a 80710 em comentário bloqueada. Retomar **somente `--preflight`** com script pinado; `--apply` ainda não executado e sujeito a autorização de reinício do Manager/risco de breve interrupção de ingestão. Nenhum status de remediação real deve ser marcado PASS antes da prova pós-mudança.
