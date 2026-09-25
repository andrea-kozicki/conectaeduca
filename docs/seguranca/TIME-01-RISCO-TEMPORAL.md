# TIME-01 — risco temporal institucional aceito no laboratório

**Data:** 25/09/2026  
**Escopo:** ConectaEduca / Experiência Criativa 8  
**Estado:** DONE_WITH_ACCEPTED_RISK

## Contexto

Os diagnósticos pré-freeze registraram NTP ativo nas VMs, porém sem
sincronização confiável com o relógio observado no pfSense. A conta acadêmica
disponível para a equipe não possui privilégio suficiente para alterar a
configuração temporal do firewall institucional.

O projeto não irá contornar essa limitação com alteração não autorizada nem
apresentar o ambiente como temporalmente sincronizado quando isso não foi
comprovado.

## Decisão

TIME-01 é encerrado por **aceitação formal de risco residual no laboratório**.

A sincronização temporal imperfeita:

- não bloqueia a arquitetura preventiva já validada;
- não altera o conteúdo dos controles de autenticação, segmentação, backup ou
  menor privilégio;
- afeta a precisão da correlação cronológica entre fontes de log distintas;
- deve ser explicitada na análise de evidências, no pentest e no relatório.

## Impacto operacional

Durante a correlação Wazuh / Suricata / WAF / pfSense / aplicação:

1. não assumir igualdade absoluta de timestamps entre fontes;
2. registrar a fonte e o timestamp original de cada evidência;
3. usar IDs de evento, IPs, portas, request IDs, assinaturas e sequência causal
   como elementos adicionais de correlação;
4. quando houver diferença de relógio observável, registrar o skew no pacote de
   evidência em vez de editar timestamps;
5. não usar a diferença temporal, isoladamente, para concluir que dois eventos
   não pertencem à mesma cadeia;
6. preservar logs brutos sem normalização destrutiva.

## Escopo da aceitação

Esta aceitação vale somente para o laboratório acadêmico atual e decorre de uma
restrição de privilégio institucional.

Ela **não** representa recomendação para produção. Em um ambiente produtivo,
firewall, hosts e sistemas de observabilidade devem utilizar fontes de tempo
confiáveis e monitoradas, com alerta para perda de sincronização.

## Gate no FREEZE-01

O freeze deve registrar:

```text
TIME01_NTP_RISK_ACCEPTED=YES
TIME01_PFSENSE_CONFIG_PRIVILEGE=UNAVAILABLE
TIME01_CROSS_SOURCE_TIMESTAMP_EXACTNESS=NOT_GUARANTEED
TIME01_SCOPE=ACADEMIC_LAB
```

Se o suporte institucional corrigir a sincronização antes do freeze, registrar
a melhoria como evidência adicional; isso não é condição para reabrir TIME-01.

## Fechamento

```text
TIME01_STATUS=DONE_WITH_ACCEPTED_RISK
TIME01_RUNTIME_MUTATION=NO
TIME01_UNAUTHORIZED_WORKAROUND=NO
```
