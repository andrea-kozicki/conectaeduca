# ConectaEduca — candidato a arquivo acadêmico 2026.11

- **Situação:** CANDIDATO / **não publicado como release final**.
- **Preparação documental:** 18/11/2026 (America/Sao_Paulo).
- **Natureza:** código-fonte, automações, documentação e evidências públicas já revisadas;
  **não é um pacote operacional das VMs nem certificação de segurança**.
- **Autoria acadêmica individual:** Andréa Kozicki; infraestrutura e apoio
  operacional institucionais, com softwares e bibliotecas de terceiros
  sujeitos às suas próprias licenças.

## Identidade e fronteira do corte

- **Repositório:** [`andrea-kozicki/conectaeduca`](https://github.com/andrea-kozicki/conectaeduca).
- **Baseline pós-consolidação das PRs #243–246:**
  [`527d6a08034beff78549b6f5757606ed302b9e68`](https://github.com/andrea-kozicki/conectaeduca/commit/527d6a08034beff78549b6f5757606ed302b9e68).
  Esse SHA é **anterior** às correções documentais deste candidato e **não**
  deve ser usado como SHA definitivo de publicação.
- **Nome sugerido para eventual tag:** `v2026.11-ec8-archive-rc1`.
  **Não criada** por este documento. Conferir colisões e aprovar a referência
  exata antes de criar tag ou release no GitHub.
- **Corte final:** `PENDENTE — registrar SHA completo após último merge,
  execução de checks e revisão de privacidade`.
- **Estado de deploy:** nenhuma alteração de runtime, dados, certificados,
  volumes, imagens ou rede deve ser executada para produzir este arquivo.

> Este documento descreve uma **candidatura à preservação acadêmica**. Um
> pacote de código versionado pode permanecer útil mesmo que o laboratório
> institucional seja desligado. Não confundir a conclusão da disciplina com
> disponibilidade futura dos serviços.

## Notas para um eventual GitHub Release

### Conteúdo preservado

1. **Aplicação e engenharia de segurança:** aplicação web PHP, documentação
   de controles, testes e workflows de CI disponíveis no repositório.
2. **Arquitetura acadêmica:** segmentação lógica entre EP125 (DMZ) e EP126
   (rede interna), pfSense, WAF, Nginx/PHP, MariaDB, OpenBao, Bacula, Ferret
   e Wazuh; camada experimental de acesso Twingate. Diagramas são
   **representações lógicas**, não topologia operacional verificada no corte.
3. **Dois ciclos de pentest:** escopo, observações, decisões de hardening,
   controles adicionados e limitações de comparação entre os ciclos A e B.
   Os testes não demonstram, isoladamente, o efeito causal do Twingate.
4. **Reconciliação seletiva das fontes:** Ferret V5/GA-06 e Wazuh
   80710 V6/PA-06 com proveniência e testes offline; os merges
   [#237](https://github.com/andrea-kozicki/conectaeduca/pull/237) e
   [#240](https://github.com/andrea-kozicki/conectaeduca/pull/240)
   **não produziram novos deploys**.
5. **Portfólio e comunicação:** autoria individual explícita, estudos de caso,
   infográficos em PNG/SVG, matriz de evidências, lições aprendidas,
   [histórico](../../CHANGELOG.md) e [metadados de citação](../../CITATION.cff).
6. **Controles sem VMs:** validação offline de sintaxe e duplicidade de
   YAML/XML, regressões em testes unitários e verificações de integridade
   para artefatos selecionados. Não equivalem a teste de inicialização ou
   telemetria real dos serviços.

### Quatro PRs consolidadas em 18/11/2026

| PR | Resultado integrado | Commit de merge |
| --- | --- | --- |
| [#243](https://github.com/andrea-kozicki/conectaeduca/pull/243) | Política de privacidade e limites de publicação | `f0bd5eeb8566024d93fec6d87139b7a0ae12c3e1` |
| [#244](https://github.com/andrea-kozicki/conectaeduca/pull/244) | Gate estático offline de YAML e XML, com regressões | `5a40e097c919f4cfb1151e037f5bda5b42ce0500` |
| [#245](https://github.com/andrea-kozicki/conectaeduca/pull/245) | Plano de encerramento e última janela da EP126 | `8330fcf81ba6822faa70929e951aeacb15a0b89f` |
| [#246](https://github.com/andrea-kozicki/conectaeduca/pull/246) | `CITATION.cff` e `CHANGELOG.md` acadêmicos | `527d6a08034beff78549b6f5757606ed302b9e68` |

### Preparação posterior à consolidação

- [PR #247](https://github.com/andrea-kozicki/conectaeduca/pull/247):
  notas de candidato a arquivo e atualização dos documentos de encerramento,
  merge `7bb0a6432deab379a605dac7467a2be751594828`.
- [PR #248](https://github.com/andrea-kozicki/conectaeduca/pull/248):
  segunda triagem das 21 PRs históricas e das seis issues operacionais,
  merge `53d60ed38425a45e97af1c950632cd29297cf3e5`.

Esses novos commits **não são a tag final de arquivamento**. O SHA final só
poderá ser registrado após todos os merges documentais autorizados e os gates
de publicação.

### Limites e riscos residuais

| Domínio | O que **não** deve ser alegado |
| --- | --- |
| **EP125 / GA-08** | Não há prova de paridade integral entre checkout final, os 22 artefatos locais inventariados anteriormente e a `main`; saúde web observada em novembro é datada |
| **EP126 / GA-06** | Dois scripts Fish locais e `RELEASE-METADATA.txt` não estão liberados para publicação; rollback real do Ferret V5 não foi ensaiado |
| **Wazuh / PA-06** | SHA do XML e alerta positivo não estabelecem cobertura E2E de todos os casos negativos e caminhos de telemetria |
| **Twingate / Zero Trust** | Falha de resolução do alias do Dashboard Wazuh e matriz RBAC/MFA de identidades distintas ainda não homologadas |
| **OpenBao e Bacula** | Recuperação pontual/healthcheck não demonstram retenção após desligamento, restore integral de backup ou auditoria completa de ACLs |
| **Pentests A/B** | Não se pode afirmar exploração de todos os PAs, paridade completa dos cenários ou redução percentual de risco atribuível exclusivamente ao Twingate |
| **Infraestrutura institucional** | Repositório e arquivos versionados não preservam, por si, VMs, snapshots, dados, redes, certificados ou autorizações |

Os documentos [estado de encerramento](../encerramento/README.md),
[inventário EP125](../portfolio/EP125-PRE-ENCERRAMENTO.md) e
[última janela EP126](../encerramento/EP126-ULTIMA-JANELA.md)
foram elaborados para distinguir preparação de execução. Se as VMs forem
desligadas antes das verificações, declarar cada item como **NÃO VERIFICÁVEL**,
sem preencher lacunas com suposições.

## Verificação offline mínima do candidato

Executar em clone limpo do **mesmo SHA escolhido para publicação**.
Os comandos abaixo não acessam VMs ou executam deploy.

```bash
git status --short --branch
git rev-parse HEAD
git diff --check

python3 scripts/evidencias/pa06_validar_80710_v6.py
python3 scripts/evidencias/checkpoint_compose_security_invariants.py --self-test
python3 scripts/evidencias/pfsense_wazuh_decoder_regression.py --self-test

python3 -m venv .venv-ce-offline
.venv-ce-offline/bin/python -m pip install 'PyYAML==6.0.3'
.venv-ce-offline/bin/python -m unittest discover -s tests/python \
  -p 'test_validar_configuracoes_offline.py' -v
.venv-ce-offline/bin/python scripts/evidencias/validar_configuracoes_offline.py
```

Em ambiente PHP compatível, verificar também `composer validate --strict
--no-check-publish` e `composer audit --locked --no-interaction`, registrando
qualquer limitação de dependência ou rede. Reexecutar CI no SHA efetivo do
candidato; **checks verdes de PRs anteriores não são prova do SHA futuro**.

## Condições antes de criar tag ou publicar release

- [x] PRs #243–246 integradas e baseline pós-consolidação registrado.
- [x] Autoria individual, histórico, citação e limitações operacionais documentados.
- [x] Procedimento offline preparado e documentado; **não significa PASS do corte futuro**.
- [ ] Reavaliar visibilidade pública do conteúdo, imagens, diffs e histórico Git;
      excluir segredos, dados pessoais e metadados institucionais não autorizados.
- [ ] Escolher o commit completo final **após** eventual merge desta preparação.
- [ ] Executar e registrar os checks no mesmo commit; classificar falhas e
      testes não executáveis sem convertê-los em PASS.
- [ ] Decidir destino das pendências de EP125/EP126 durante a última janela
      autorizada; anotar como **NÃO VERIFICÁVEL** o que não for comprovado.
- [ ] Confirmar que a tag sugerida não existe e aprovar nome, SHA e modalidade
      de publicação (`draft`/pré-lançamento/arquivo público).
- [ ] Decidir separadamente se haverá licença de reutilização; a presença de
      `CITATION.cff` **não** cria licença.
- [ ] Só então criar a tag e o release; não anexar dumps, TARs privados,
      certificados, chaves, tokens, capturas brutas ou snapshots institucionais.

**Texto curto apropriado a uma futura descrição de release:**

> Pacote de preservação acadêmica do ConectaEduca (Experiência Criativa 8,
> 2026), desenvolvido individualmente por Andréa Kozicki. Reúne código-fonte,
> arquitetura documentada, testes estáticos, estudos de caso e os registros dos
> pentests A e B. Não contém as VMs, dados operacionais ou comprovação de
> homologação ponta a ponta. Riscos residuais e limites estão documentados.

**Gate de publicação:** consultar a
[matriz de prontidão e autorização](GATE-PREPUBLICACAO-ACADEMICA-2026-11-18.md)
e a [issue de acompanhamento #249](https://github.com/andrea-kozicki/conectaeduca/issues/249)
antes de aprovar o nome, a tag e o SHA do corte.
