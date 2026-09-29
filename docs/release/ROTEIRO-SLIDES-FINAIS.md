# Roteiro dos slides finais — ConectaEduca

Apresentação alvo: ~10 minutos.

## 1. Problema e objetivo (~45 s)
ConectaEduca + quatro objetivos: movimento lateral, escalação, evasão e vazamento.

## 2. Arquitetura final (~60 s)
Diagrama com EP125/DMZ, EP126/interna, pfSense, WAF e serviços internos.

## 3. Menor privilégio (~60 s)
RBAC/MFA, identidade `teste`, OpenBao humano/workload, Bacula/Wazuh/Bacularis/phpMyAdmin read-only e zero-sudo.

Já pode entrar no slide: CRED-01 PASS nas duas VMs e exemplos de allow/deny.
Não afirmar o corte final de sudo até o runtime check pós-sync.

## 4. Detecção em profundidade (~60 s)
WAF/Suricata/FIM/Ferret → Wazuh → correlação/evidência. Usar no máximo 1–2 screenshots.

Já pode entrar: WAF rule 110300 pós-reboot e Suricata→Wazuh. Deixar
pfSense→Wazuh como placeholder até OPS-01.

## 5. Resiliência/Bacula (~60 s)
MariaDB dump + OpenBao Raft + Catalog + Recovery State → backup → perda controlada → restore → SHA-256. Citar risco do mesmo domínio físico.

## 6. Pentest S01–S13 (~75 s)
Agrupar por objetivo, não mostrar tabela minúscula com 13 linhas.

Estrutura pronta:
- movimento lateral: T1046/T1021/T1078;
- escalação: T1078/T1611/T1552.007;
- evasão: T1562.001;
- vazamento: T1552.001/T1552.004/T1041.

Preencher somente resultados observados depois da execução.

## 7. Pentest A (~60 s)
[PREENCHER após execução] — PASS, achados, correções e evidências-chave.

## 8. Twingate + Pentest B (~75 s)
[PREENCHER após execução] — comparar somente vetores repetidos.

## 9. Riscos residuais e conclusão (~60 s)
TIME-01, backup, restrições institucionais e itens FUTURE relevantes.

Já pode entrar:
- TIME-01 = risco temporal aceito no laboratório;
- Bacula = mesmo domínio físico da EP126;
- OPS-01 = dependência institucional até marker assistido;
- Snyk final = artifact CI dedicado sem sudo, quando produzido.

## Plano B
Se uma WebGUI falhar: screenshot + TXT/checkpoint + SHA-256 + esperado/observado. Nunca mostrar segredo.
