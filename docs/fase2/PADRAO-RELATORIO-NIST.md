# Padrão de reporte da Fase 2 — NIST SP 800-115

Este documento define o formato canônico de registro dos testes da Fase 2.

## Metodologia primária

O ciclo segue o NIST SP 800-115:

1. Planning;
2. Discovery;
3. Attack;
4. Reporting.

MITRE ATT&CK permanece como referência para TTPs e STRIDE como apoio para classificação de ameaças.

## Estrutura obrigatória de cada subteste

Cada subteste deve registrar:

1. **Objetivo de segurança** — qual risco ou boundary está sendo avaliado.
2. **Hipótese ofensiva** — como um atacante tentaria converter a condição em acesso ou impacto.
3. **Superfície/controle** — serviço, arquivo, identidade, permissão ou fluxo.
4. **Procedimento** — técnica usada e limites de segurança.
5. **Evidência** — timestamp, contexto, resultado, arquivo e SHA-256.
6. **Conclusão permitida** — o que o resultado demonstra diretamente.
7. **Limite da evidência** — o que não pode ser concluído sem teste adicional.
8. **Classificação** — PASS, observação, finding ou TEST_ERROR.
9. **Próximo passo** — Attack adicional, correção, reteste ou encerramento do subescopo.

## Critérios

- **PASS:** nenhum caminho explorável foi demonstrado nas superfícies e técnicas avaliadas.
- **Observação:** fato relevante para cobertura/operação/risco, sem prova suficiente de vulnerabilidade.
- **Finding:** caminho reproduzível com influência indevida, violação de controle ou impacto demonstrado.
- **TEST_ERROR:** execução inválida/incompleta; não conta como PASS nem finding.

## Estratégia ofensiva complementar

Resultados anteriores podem ser revisitados com enumeração mais ofensiva.

Quando surgir candidate plausível, a análise deve avançar para prova controlada e reversível de impacto, respeitando as regras de engajamento:

- sem brute force;
- sem DoS;
- sem persistência ou malware;
- sem sudo/su como contorno;
- sem shell privilegiado;
- sem imprimir segredos reais.

## Modelo de finding

Um finding deve conter:

- título;
- ativo/componente;
- pré-condição;
- hipótese/ataque;
- evidência;
- impacto demonstrado;
- MITRE ATT&CK quando houver mapeamento claro;
- severidade;
- correção;
- reteste.

## Ponto de retomada

Em 08/10/2026, a retomada deve começar pelo **PA-03.B na EP125: SUID/SGID + capabilities**. O PA-03.A já foi executado e não precisa ser repetido.
