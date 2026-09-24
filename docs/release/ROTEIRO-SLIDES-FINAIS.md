# Roteiro dos slides finais — ConectaEduca

Apresentação alvo: ~10 minutos.

## 1. Problema e objetivo (~45 s)
ConectaEduca + quatro objetivos: movimento lateral, escalação, evasão e vazamento.

## 2. Arquitetura final (~60 s)
Diagrama com EP125/DMZ, EP126/interna, pfSense, WAF e serviços internos.

## 3. Menor privilégio (~60 s)
RBAC/MFA, identidade `teste`, OpenBao humano/workload, Bacula/Wazuh/Bacularis/phpMyAdmin read-only e zero-sudo.

## 4. Detecção em profundidade (~60 s)
WAF/Suricata/FIM/Ferret → Wazuh → correlação/evidência. Usar no máximo 1–2 screenshots.

## 5. Resiliência/Bacula (~60 s)
MariaDB dump + OpenBao Raft + Catalog + Recovery State → backup → perda controlada → restore → SHA-256. Citar risco do mesmo domínio físico.

## 6. Pentest S01–S13 (~75 s)
Agrupar por objetivo, não mostrar tabela minúscula com 13 linhas.

## 7. Pentest A (~60 s)
[PREENCHER após execução] — PASS, achados, correções e evidências-chave.

## 8. Twingate + Pentest B (~75 s)
[PREENCHER após execução] — comparar somente vetores repetidos.

## 9. Riscos residuais e conclusão (~60 s)
TIME-01, backup, restrições institucionais e itens FUTURE relevantes.

## Plano B
Se uma WebGUI falhar: screenshot + TXT/checkpoint + SHA-256 + esperado/observado. Nunca mostrar segredo.
