# AUDIT-01 — guia de triagem Lynis para o ConectaEduca

## Objetivo

Reduzir improviso depois das execuções do Lynis sem pré-classificar findings que
ainda não existem.

Este guia **não é uma allowlist** e não converte automaticamente IDs Lynis em
`N_A_LAB`, `JA_MITIGADO` ou `RISCO_ACEITO`. A classificação continua
dependendo da mensagem concreta, do host onde ela apareceu e das evidências do
projeto.

## Regra de decisão

Para cada linha de `TRIAGEM-LYNIS.tsv`, responder nesta ordem:

1. **O finding descreve um estado real do host?**
   - se não, investigar erro de detecção/escopo antes de classificar;
2. **o controle é aplicável ao papel daquela VM?**
   - se não, `N_A_LAB`, com justificativa técnica específica;
3. **há evidência posterior que já mitiga exatamente o risco apontado?**
   - se sim, `JA_MITIGADO` e referenciar essa evidência;
4. **é corrigível sem violar arquitetura, requisito acadêmico ou boundary
   institucional?**
   - se sim, `APLICAVEL` e registrar ação concreta;
5. **é um risco real que permanecerá conscientemente?**
   - usar `RISCO_ACEITO`, descrever impacto, escopo e controle compensatório.

Nunca escolher uma classe apenas para aumentar o hardening index.

## Referências do projeto para cruzamento

| Tema do finding | Evidência/controle a consultar |
|---|---|
| exposição de rede / portas | pfSense, inventário de portas, Compose security invariants |
| serviço privilegiado / capabilities | hardening dos Compose + runtime evidence |
| Docker socket / host network | CI-SEC-01 e exceção explícita do Twingate |
| autenticação e senha | CRED-01 / identidade `teste` |
| OpenBao/secrets | policies, AppRole, userpass e custódia Shamir |
| logs/auditoria | Wazuh, Suricata, WAF, audit OpenBao |
| backup | BAC-04 E2E + BAC-05 decisão de recorrência manual |
| relógio/NTP | TIME-01 — risco temporal institucional aceito |
| banco de dados | MariaDB hardening; Catalog/PgBouncer TLS/SCRAM |
| integridade de arquivos | Wazuh FIM e evidências específicas |
| atualizações/pacotes | avaliar impacto e necessidade; não fazer upgrade automático |
| senha mínima/aging | confrontar com a restrição acadêmica; não auto-classificar |
| MAC/AppArmor | avaliar o finding concreto; a retirada de AppArmor como componente dedicado não torna qualquer finding automaticamente N/A |

## Pontos que exigem cautela especial

### NTP / clock

TIME-01 já registra uma limitação institucional. Um finding Lynis temporal pode
ser candidato a `RISCO_ACEITO` **somente se** descrever a mesma condição já
documentada. Não usar TIME-01 para mascarar outro problema temporal distinto.

### Backup

O Lynis pode não reconhecer o desenho Bacula do laboratório. Se aparecer um
finding genérico de ausência de backup, comparar com BAC-04/BAC-05 antes de
classificar. Se o finding apontar outra propriedade — por exemplo permissões,
retenção, storage ou freshness — analisar essa propriedade separadamente.

### Política de senha

A identidade acadêmica `teste` possui uma restrição didática própria. Se o
Lynis criticar comprimento, aging ou política global, separar:

- requisito acadêmico da conta de teste;
- política global do host;
- exposição efetiva;
- compensações e remoção/desativação após o pentest.

Não relaxar política global apenas para alinhar a ferramenta.

### Kernel/sysctl

Não aplicar `sysctl` em lote. Verificar:

- se o finding afeta o tráfego/serviço usado pela VM;
- se conflita com Docker, pfSense, xrdp/Guacamole ou requisitos do laboratório;
- se já existe hardening equivalente em outra camada;
- rollback e impacto antes de qualquer mudança.

### Serviços detectados

Um daemon existente não é automaticamente vulnerabilidade. Confirmar:

- necessidade no papel da VM;
- bind de rede;
- usuário/capabilities;
- autenticação;
- exposição pelo firewall;
- logging e monitoramento.

## Evidência mínima por classificação

### APLICAVEL

Registrar:

- ID e mensagem Lynis;
- por que é relevante ao host;
- ação planejada;
- evidência depois da correção ou motivo para converter em risco aceito.

### JA_MITIGADO

Registrar:

- controle compensatório específico;
- arquivo/card/evidência que o comprova;
- por que o Lynis não o reconheceu.

### N_A_LAB

Registrar:

- qual pressuposto do teste Lynis não existe no desenho;
- papel real da VM;
- por que não há superfície equivalente.

### RISCO_ACEITO

Registrar:

- risco técnico;
- impacto;
- motivo para não corrigir;
- escopo da aceitação;
- controle compensatório;
- condição de reabertura.

## Consolidação depois das duas VMs

Depois de finalizar as duas triagens:

```bash
python3 scripts/evidencias/audit01_consolidar_duas_vms.py \
  --ep125-dir ~/conectaeduca-audit01-lynis-ep125-pucpr-<UTC> \
  --ep126-dir ~/conectaeduca-audit01-lynis-ep126-pucpr-<UTC>
```

O consolidador:

- verifica `SHA256SUMS-RAW` e `SHA256SUMS-FINAL` das duas VMs;
- recusa triagem não finalizada;
- compara TEST_IDs comuns e exclusivos;
- não altera classificações;
- destaca somente `APLICAVEL` e `RISCO_ACEITO` em um documento de prioridade;
- gera resumo consolidado e novo `SHA256SUMS`.

Saída:

```text
~/conectaeduca-audit01-consolidado-<UTC>/
  MATRIZ-COMPARATIVA-LYNIS.tsv
  ACHADOS-PRIORITARIOS.md
  RESUMO-AUDIT01-CONSOLIDADO.txt
  SHA256SUMS
```

## Resultado esperado antes do FREEZE-01

AUDIT-01 pode ser considerado pronto para o freeze quando:

- EP125 e EP126 possuem pacotes RAW/FINAL válidos;
- nenhuma linha permanece pendente;
- todo `APLICAVEL` possui correção ou decisão explícita;
- todo `RISCO_ACEITO` está refletido na matriz pré-freeze;
- o consolidado das duas VMs passa;
- hardening index é reportado como dado auxiliar, nunca como nota.
