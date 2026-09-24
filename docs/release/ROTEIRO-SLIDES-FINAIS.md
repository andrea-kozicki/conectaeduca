# Roteiro de slides finais — ConectaEduca

## Princípio

Apresentação de aproximadamente 10 minutos. Cada slide deve responder uma pergunta e usar evidência do projeto, não texto excessivo.

## Slide 1 — Problema e objetivo

**Pergunta:** o que foi protegido?

- ConectaEduca;
- arquitetura segura para aplicação, DMZ e rede interna;
- quatro objetivos de teste: movimento lateral, escalação, evasão e vazamento.

Visual: arquitetura resumida.

Tempo: ~45 s.

## Slide 2 — Arquitetura final

**Pergunta:** como o ambiente foi separado?

Mostrar:

- EP125/DMZ;
- EP126/interna;
- pfSense;
- WAF;
- MariaDB/OpenBao/Wazuh/Ferret/Bacula;
- fluxos essenciais.

Visual: diagrama final legível.

Tempo: ~60 s.

## Slide 3 — Menor privilégio e identidade

**Pergunta:** como evitamos que uma credencial vire administração total?

Mostrar:

- RBAC/MFA da aplicação;
- `teste` como identidade mínima;
- OpenBao humano vs workload;
- Bacula Console read-only;
- Wazuh/phpMyAdmin/Bacularis read-only;
- zero-sudo durante pentest.

Tempo: ~60 s.

## Slide 4 — Detecção e defesa em profundidade

**Pergunta:** como um evento vira evidência?

Fluxo visual:

```text
origem do evento
  -> WAF / Suricata / FIM / Ferret
  -> Wazuh
  -> correlação / evidência
```

Usar 1 ou 2 screenshots reais, não catálogo de telas.

Tempo: ~60 s.

## Slide 5 — Resiliência e Bacula

**Pergunta:** conseguimos recuperar?

Mostrar:

- MariaDB logical dump;
- OpenBao Raft snapshot;
- Catalog dump;
- Recovery State;
- backup -> perda controlada -> restore -> SHA-256.

Registrar o risco residual do mesmo domínio físico.

Tempo: ~60 s.

## Slide 6 — Pentest S01–S13

**Pergunta:** o que foi testado?

Agrupar visualmente:

- movimento lateral;
- escalação;
- evasão;
- vazamento;
- privacidade transversal.

Não listar 13 linhas pequenas; mostrar grupos e citar Sxx.

Tempo: ~75 s.

## Slide 7 — Resultados do Pentest A

**Pergunta:** onde o baseline resistiu e onde houve achado?

[PREENCHER depois do Pentest A.]

Usar:

- PASS;
- FAIL/achados;
- correções;
- evidências-chave.

Tempo: ~60 s.

## Slide 8 — Twingate e Pentest B

**Pergunta:** o que mudou com Zero Trust?

[PREENCHER após Pentest B.]

Comparar somente vetores repetidos em condições comparáveis.

Visual: tabela A × B curta.

Tempo: ~75 s.

## Slide 9 — Riscos residuais e conclusão

**Pergunta:** o que ainda fica como risco ou limitação?

Possíveis itens, conforme estado final:

- TIME-01;
- backup no mesmo domínio físico;
- restrições institucionais;
- itens FUTURE não bloqueantes.

Encerrar com o que foi efetivamente demonstrado, não com promessa.

Tempo: ~60 s.

## Backup da apresentação

Se WebGUI falhar durante a avaliação, ter para cada controle crítico:

- screenshot;
- TXT/checkpoint;
- SHA-256;
- resultado esperado/observado.

Não demonstrar segredos em tela.
