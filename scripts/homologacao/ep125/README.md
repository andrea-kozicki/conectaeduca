# ConectaEduca — Kit de homologação EP125 (30/10/2026)

Este diretório disponibiliza **um script consolidado com 10 etapas** para reexecução controlada na EP125. Reconstruído a partir das rotinas de homologação; **não é uma reprodução byte a byte** dos comandos originais.

## Como executar a partir do GitHub

Na **EP125**, dentro do checkout do repositório, primeiro confira a branch e o estado do trabalho local:

```bash
git status --short
git branch --show-current
```

Se já estiver na branch `docs/fase3-arquitetura-zero-trust-20261021` e **não houver mudanças locais a preservar no arquivo do kit**, atualize com `git pull --ff-only`. Não use `git reset --hard` nem troque de branch com alterações pendentes.

Depois execute uma etapa por vez:

```bash
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 16A2
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 16A3
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 16A4
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 16B1
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 17A
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 17A1
bash scripts/homologacao/ep125/ce_homolog_ep125.sh 17B0
```

**16B** reproduz o diagnóstico histórico de loopback incorreto e não é necessária na revalidação normal.

**16B2** envia dois GETs controlados ao WAF (baseline e payload sintético). Só execute em janela autorizada:

```bash
CE_ALLOW_HTTP_TEST=YES bash scripts/homologacao/ep125/ce_homolog_ep125.sh 16B2
```

**16C** não envia tráfego. Requer o marcador gerado na 16B2 e intervalo correto dos logs:

```bash
MARCADOR='CEWAF16B2_...' INICIO='2026-10-30T18:31:00-03:00' FIM='2026-10-30T18:34:00-03:00' bash scripts/homologacao/ep125/ce_homolog_ep125.sh 16C
```

## Escopo, resultados e limitações

- **16A2–16A4:** inspeção do CRS e do funcionamento de `docker exec -i`. Etapas reconstruídas, não reproduzem os erros históricos.
- **16B/16B1:** diagnóstico do destino HTTPS e portas Docker.
- **16B2/16C:** teste sintético de bloqueio e correlação com logs; não substituem pentest abrangente.
- **17A/17A1:** contagem de indicadores CSRF e cobertura de código; **não validam funcionalmente CSRF**.
- **17B0:** preflight estático de RBAC; **não executa teste RBAC negativo autenticado**.

A evidência de 30/10 registrou baseline 200, requisição sintética 403 e IDs CRS correlacionados. Na 17A1 foram observados 115 arquivos PHP, seis JS, 120 legíveis e zero referências aos termos pesquisados; investigar antes de concluir ausência de CSRF.

Os arquivos de evidência são gravados em `~/ConectaEduca_Fase2_Evidencias/EP125/HOMOLOG/`, com SHA-256 impresso ao final. O diário `~/ConectaEduca_Fase2_Evidencias/EP125/diario.md` recebe adendo após backup, quando existente.

**Não versionar logs brutos, tokens, cookies, segredos, dumps, credenciais ou dados pessoais.** O repositório contém scripts, não os TXT brutos da VM.

## GitHub Actions versus execução na VM

O repositório já utiliza GitHub Actions para CI, PHPUnit e verificações estáticas. **Este kit não é executado automaticamente pelo GitHub Actions**: os testes dependem de contêineres, rede e logs da EP125. O GitHub é a fonte versionada; a execução ocorre na VM. Não foi criado runner self-hosted, workflow de acesso remoto ou acionamento automático de testes ativos.

## Estado

Publicação apenas na branch de documentação da Fase 3. Sem merge em `main`, sem alterações de configuração da EP125/EP126. A issue #201 permanece aberta, com CSRF funcional, RBAC negativo e rollback pendentes.
