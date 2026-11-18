# EP125 — Kit de preservação antes do encerramento acadêmico

**Responsável pelo projeto:** Andréa Kozicki  
**Situação:** material **preparado sem acesso às VMs** em 18/11/2026. Nenhuma execução, cópia, deploy ou recuperação é afirmada aqui.  
**Objetivo:** reduzir a perda de evidências e arquivos de configuração próprios do projeto quando as VMs institucionais forem desativadas na semana seguinte.

## Prioridade e fronteira de autorização

No último inventário (17/11), a EP125 executava WAF, Nginx e PHP-FPM com healthchecks saudáveis, mas **22 arquivos GA-08** estavam fora do Git. Os três arquivos `compose.ga08-*.candidate.yml` da EP125 coincidiam byte a byte com as cópias do pacote PA-02 local, de acordo com o inventário daquele dia. Isso não prova que os demais scripts tenham sido preservados.

**Não** desligar/reiniciar serviços, restaurar snapshots, alterar `main`, executar instaladores, exportar volumes nem copiar dados institucionais sem autorização explícita. Esta fase é de **inventário e custódia**, não de reimplantação.

## Checklist para a última sessão autorizada na EP125

1. Confirmar `hostname` e identidade, janela de acesso e destino autorizado dos arquivos do trabalho.
2. Coletar o estado do Git **sem `git pull`, `reset`, `clean`, `checkout` ou `stash`**.
3. Executar o [manifesto somente leitura](../../scripts/evidencias/ep125_pre_encerramento_manifest.sh), após conferir seu conteúdo e sintaxe. Se o arquivo ainda estiver apenas na PR de revisão, obtê-lo por meio de checkout de trabalho **separado**, sem alterar `/opt/conectaeduca`.
4. Comparar hashes com referências do inventário anterior, inspecionar os candidatos GA-08 em busca de segredos, endpoints institucionais, nomes de usuário ou dados reais. A saída do manifesto contém **nomes relativos e hashes**, não conteúdo de arquivos.
5. Sob autorização, preservar em local pessoal seguro **somente artefatos do projeto com publicação/custódia permitidas**. Não transportar segredos, certificados privados, logs reais, dumps, imagens TAR institucionais, snapshots nem backups de terceiros.
6. Documentar a cadeia de custódia (data, ativo, responsável, hashes, decisão de inclusão/exclusão), antes de preparar uma PR específica para GA-08.
7. Verificar o plano da EP126: Fish local ainda não publicado e backup pré-reconciliação. Um backup existente **na própria VM** não subsiste necessariamente ao desligamento.

## Itens pendentes conhecidos na EP125

| Grupo | Arquivos | Estado no último inventário |
| --- | --- | --- |
| Compose GA-08 | `compose.ga08-socket.candidate.yml`, `compose.ga08-dual-socket.candidate.yml`, `compose.ga08-runtimefix.candidate.yml` | Locais, não versionados; três hashes coincidiram com o pacote PA-02 |
| Nginx/PHP-FPM | `deploy/dmz/ga08/*.candidate.conf` (três arquivos) | Locais, não versionados; revisar paths e política de divulgação |
| Change control | `docs/release/GA08-17B-CHANGE-CONTROL-EP125-20261102.md` | Local, não versionado |
| Testes e diagnóstico | 12 scripts Python `scripts/ga08-*.py` | Sintaxe Python aprovada; comportamento completo não homologado pelo simples `py_compile` |
| Execução e rollback | Três scripts Bash `ga08-implantacao-controlada`, `ga08-preparar-sockets`, `ga08-rollback-controlado` | Sintaxe Bash aprovada; **não executar** no inventário |

O inventário original identificou **22 caminhos de arquivos** (3 compose + 3 conf + 1 documento + 12 Python + 3 Bash).

### Hashes de referência dos três Compose (17/11/2026)

| Candidato | SHA-256 do inventário |
| --- | --- |
| `compose.ga08-socket.candidate.yml` | `5e6ce7dbab62b104a1448a84e23690c86d07ceccbbf36bfad9b8b91fb344dadc` |
| `compose.ga08-dual-socket.candidate.yml` | `fbf5c3aac42e02c40d09cf2fc0e19ccf634570a0d2049b2fbbceb4e49d191d51` |
| `compose.ga08-runtimefix.candidate.yml` | `9fb109e9b2da4b397c43c541d7120a68b682cc745eb6b3298061d5927e3aeb84` |

Conferir o novo hash antes de comparar: um arquivo pode ter sido alterado desde o inventário.

## Como executar o manifesto — somente quando houver acesso

No Bash da EP125, a partir de uma **cópia de revisão separada** que contenha o script, apontando explicitamente para o checkout operacional que guarda os candidatos GA-08:

```bash
bash -n scripts/evidencias/ep125_pre_encerramento_manifest.sh
bash scripts/evidencias/ep125_pre_encerramento_manifest.sh --repo /opt/conectaeduca
```

O script se recusa a continuar se o hostname não corresponder à EP125 esperada **ou se o caminho-alvo não for informado exatamente**. Pode ficar numa worktree de revisão: o inventário sempre apontará para `/opt/conectaeduca`, onde os arquivos locais foram identificados. **Não pede sudo, não cria arquivos e não altera runtime**. É aceitável salvar sua saída por mecanismo autorizado, mas revise até os metadados antes de publicar.

## Registros finais de encerramento

| Questão | Resultado esperado | Como registrar |
| --- | --- | --- |
| Todos os 22 arquivos localizados? | Lista de presentes, ausentes e hashes | Manifesto sem dados de conteúdo |
| Algum dado sensível? | Classificação por arquivo | Registro local seguro, sem reproduzir o valor |
| O que pode ir ao Git? | Somente fonte/configuração sanitizada e autorizada | PR de reconciliação GA-08 com revisão |
| O que permanece fora do Git? | Segredos, dados reais, dumps, TAR, snapshots | Motivo e custódia institucional |
| Como descrever o estado final? | **Preservado**, **não preservado** ou **não verificável** | Nota pública com data e limite |

O portfólio deve continuar útil mesmo se a VM desaparecer. Sua integridade depende de **documentar as lacunas**, não de fingir que os arquivos locais foram automaticamente integrados.
