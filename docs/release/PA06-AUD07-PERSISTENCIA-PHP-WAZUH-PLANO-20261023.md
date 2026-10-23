# PA-06/AUD07 — proposta de persistência de auditoria PHP e coleta Wazuh

> **DRAFT / NÃO IMPLANTADO — 23/10/2026.** Esta proposta não autoriza copiar logs, criar diretórios na VM, modificar o Wazuh Manager, executar Compose, reiniciar/recriar contêiner ou encerrar o achado. Requer decisão de privacidade/retenção e janela institucional. Compatível com o PR #202 (PHP 8.5.12), que foi incorporado à main sem implantação automática.

## 1. Evidência e baseline

- **EP125-F2-0009:** contêiner PHP-FPM saudável com runtime 8.5.9; `audit.log` existe, 25.851 bytes, modo 0644, modificado pela última vez em 14/10/2026 23:08:49 UTC; Wazuh Agent ativo; coleta PHP não comprovada.
- **EP125-F2-0010/0011:** SHA-256 do conteúdo do arquivo estável entre medições (`d5ef6ac88886b59d81a2b361447bd6cc62d511f282eb1355e2600c31f4de1ff2`); plano de preservação não executou cópia.
- **EP125-F2-0012:** imagem PHP-FPM 8.5.12 candidata construída/testada com sucesso em tag separada, sem alteração do contêiner ativo.
- **EP125-F2-0013:** PHP UID/GID 82:82, root filesystem somente leitura; `storage/logs` em tmpfs; `/var/log` em ext4; Wazuh Agent ativo; `shared/agent.conf` local presente mas não inspecionado, configuração remota e ingestão E2E não testadas; nenhuma cópia, diretório, Compose, restart ou patch de runtime aplicado.
- **EP125-F2-0014 (23/10 18:03:58 BRT):** serviço Wazuh ativo; conta `wazuh` UID 129/GID 138; **processo `wazuh-logcollector` atualmente UID 0 (root), GID 138**; `getfacl`, `setfacl` e `logrotate` presentes. `ossec.conf` e `/var/ossec/etc/shared/agent.conf` locais não referenciam o audit.log PHP nos padrões verificados; policy remota do Manager **não avaliada**, recepção E2E não testada. O preflight não alterou permissões, serviços ou arquivos.
- **EP125-F2-0015 (23/10, 18:14:01–18:14:02 BRT):** tentativa de preservação com `CE_EP125_AUDIT_PRESERVAR_PREPATCH_v2.sh --apply --approved`, RC=1. O pré-teste confirmou origem com 25.851 bytes e hash igual ao anterior, mas `docker cp` retornou **`Could not find the file .../storage/logs/audit.log in container`**. **NÃO há cópia comprovada.** O script v2 criou a árvore privada `root:root 0700` e uma pasta de execução antes da transferência; conferir o estado desses diretórios, sem remover evidências por suposição. O fato de `docker exec` conseguir ler o arquivo e `docker cp` falhar sugere diferença no caminho de transferência/arquivo tmpfs, não prova desaparecimento da fonte. Preparado localmente script de contingência `CE_EP125_AUDIT_PRESERVAR_PREPATCH_v3.sh` usando fluxo `docker exec` → arquivo privado com `dd`, sem exibir conteúdo, confere hashes de origem antes/depois e arquivo copiado, impede recriação em caso de inconsistência. **Ainda NÃO executado na VM**; não marcar salvaguarda concluída até RC=0 e hashes iguais.
- Código fonte: `src/Security/AuditLogger.php` produz **um objeto JSON por linha** com timestamp, evento, IP, user-agent, user_id e contexto sanitizado por nomes de chaves conhecidos. Metadados permanecem potencialmente pessoais.
- Repo: `deploy/dmz/compose.vm.yml` define **três tmpfs** PHP: `/tmp`, `storage/logs` e `storage/keys`. O grupo `conectaeduca-dmz` no repositório não referencia o arquivo PHP. O servidor pode ter policy diferente da cópia no Git: validar configuração efetivamente distribuída.

## 2. Mudança declarativa isolada

`deploy/dmz/compose.audit-persistent.yml` é um **overlay opcional**, não substitui ou edita `compose.vm.yml`. A tag Compose `!override` (exige suporte no Compose local; EP125 tinha v5.5.1 em 23/10) substitui a lista tmpfs para **manter /tmp e storage/keys temporários e REMOVER apenas storage/logs**. Um bind RW para `/var/log/conectaeduca/php-audit` fornece persistência no ext4 da EP125. O diretório deve existir ANTES do deploy; `create_host_path: false` impede criação implícita pelo Docker.

**Atenção à ordem:** nove arquivos Compose constam dos labels da instância atual, nesta ordem:
1. `compose.yml`
2. `compose.database.yml`
3. `compose.app-secrets.yml`
4. `compose.waf.yml`
5. `compose.waf-tls.yml`
6. `compose.waf-policy.yml`
7. `compose.host.yml`
8. `compose.vm.yml`
9. `compose.database-tls.yml`

O overlay novo seria **o décimo arquivo**, sempre por último, numa execução expressamente aprovada. O instalador legado `scripts/implantacao/vms/20-dmz/22-preparar-dmz-fase1.sh` tem apenas **oito** overlays e pode disparar build/up de vários serviços: **NÃO executar o instalador legado para aplicar este PR**. Não imprimir `docker compose config` integral; valores de ambiente e caminhos sensíveis podem aparecer. Validar a configuração composta com verificador que reporte somente os destinos e valores booleanos necessários.

## 3. Preparação proposta do host (GATE DE APROVAÇÃO)

Dois propósitos separados:
- **Guarda de evidência pré-patch (não operacional):** `/var/backups/conectaeduca-private/ep125/pa06-aud07`, toda a árvore privada `root:root 0700`, cópia(s) root:root 0600, SHA-256 e carimbo UTC, sem colar eventos no chat, Trello ou Git. Uma cópia no mesmo disco da VM **não é backup independente**.
- **Auditoria operacional persistente:** `/var/log/conectaeduca/php-audit` em ext4, com identidade de escrita **numérica** 82:82 para o PHP, proteção contra leitura não autorizada e travessia mínima de diretórios superiores. O `wazuh-logcollector` da EP125 está rodando como **root (UID 0, GID 138)**, conforme EP125-F2-0014, e consegue ler arquivos locais restritos segundo suas capacidades atuais. Não abrir permissão geral só para satisfazer Wazuh. Se houver decisão de reduzir privilégios para UID 129, projetar ACLs mínimas de **leitura no arquivo e travessia nos diretórios** e retestar efetivamente a coleta. Não usar chmod 777 nem chown recursivo em /var/log.

O `audit.log` atual tem modo 0644, permissivo para dados pessoais. Planejar modo 0640 ou 0600 + ACL de leitura para o processo Wazuh (dependendo de seu usuário/grupos reais). Verificar também umask da aplicação e comportamento na rotação/recriação do arquivo: o PHP usa `file_put_contents(... FILE_APPEND | LOCK_EX)` e arquivos novos podem assumir modo dependente de umask.

**Planejamento da rotação:** `logrotate` está instalado mas a configuração ativa não foi examinada no EP125-F2-0014. Preferir estratégia de **rename + create com proprietário numérico 82:82 e modo restritivo (por ex. 0640)**, porque o `AuditLogger.php` abre/fecha o arquivo em cada evento com `FILE_APPEND|LOCK_EX`. Validar sob concorrência se há lacuna durante a troca; testar `delaycompress` quando necessário e evitar `copytruncate` sem evidência de que o risco de perda de linhas é aceitável. Conferir permissões também quando o PHP recriar espontaneamente o arquivo (umask). Não fixar `daily`, `rotate N`, tamanho ou compressão antes da política institucional. Na política Wazuh, verificar qual tratamento é dado ao arquivo quando a rotação troca o inode e confirmar entrega de eventos antes/depois da rotação.

**Gate de retenção:** decidir períodos para evidência bruta, auditoria operacional, cópias e eventos enviados ao Manager; finalidade de tratamento, quem acessa, cifragem/backups, descarte e incidente. `ext4` no mesmo disco garante persistência frente à recriação do contêiner, mas não frente à perda da VM/disco. Logrotate, compressão/rotação sem lacunas e proteção pós-rotação exigem plano e teste próprios antes de produção.

## 4. Procedimento de transição proposto (não executar sem change control)

1. Registrar autorização do laboratório, finalidade/retencão dos registros pessoais, operadores e janela/rollback; identificar snapshot do suporte e política de armazenamento.
2. Confirmar estado do PHP, hash/tamanho do `audit.log` e da imagem atual; fazer **cópia privada íntegra** do arquivo a partir do tmpfs para host autorizado, com comparação de SHA-256 e evidência de custódia, sem mostrar conteúdo.
3. Preparar diretórios e ACL/modes restritos; verificar com UID 82/GID 82 que PHP escreverá, e com usuário real do Wazuh que conseguirá ler, sem exposição a outros.
4. Planejar manutenção de tráfego/escritas antes do cutover. **Nunca parar/recriar PHP enquanto a única cópia válida estiver em tmpfs.** Em janela, garantir que não haverá novos append concorrentes após a cópia final; se hash de origem divergir ou houver escrita, não prosseguir sem reconciliação final.
5. Validar composição efetiva **com dez overlays** e o estado de outros serviços, sem vazar variáveis; confirmar que `/tmp` e `storage/keys` seguem tmpfs, `storage/logs` é bind RW, demais mounts/ports/secrets/DB TLS continuam iguais.
6. Planejar promoção/rollback por imagem ID e runtime PHP 8.5.12 do PR #202, separado da mudança de log quando possível. Não usar `docker compose up -d` global. Não sobrescrever `:dmz` ou contêiner em execução sem janela autorizada.
7. Após transição, conferir dados antigos + evento sintético autorizado, alterações do hash e persistência após ciclo **controlado**, status PHP e WAF/Nginx, DB/TLS, login/MFA/RBAC/CSRF e auditoria; não confundir saúde do serviço com sucesso de segurança.
8. A política Wazuh **será revisada no Manager/EP126** antes de distribuição ao agente DMZ. Modelo: `deploy/interna/wazuh/agent/conectaeduca-php-audit-localfile.xml.example` com `log_format=json`, `location=/var/log/conectaeduca/php-audit/audit.log`. Verificar duplicidades e estado da policy remota `conectaeduca-dmz`; validar `verify-agent-conf` e recebimento E2E do evento sintético com redaction e controle de acesso.
9. Observar rotação/retencão e consistência do arquivo no host. Somente após evidência ponta a ponta fechar PA-06/AUD07. A triagem de outros alerts Wazuh é item separado.

## 5. Falhas e rollback

- Se diretório operacional inexiste, UID 82 não consegue escrever, ACL dá erro ou Compose não suporta `!override`: **não implantar**.
- Se hash pré-cópia/final divergir sem explicação ou surgirem eventos em trânsito: **não recriar**; preservar todas as versões e reconciliar manualmente com responsável.
- Se ambiente/regressão falhar após uma transição autorizada: manter o bind/arquivo persistente protegido e preservar logs gerados durante a janela; reverter imagem/Compose pela sequência aprovada, evitando montar novamente tmpfs sem retirar primeiro os novos eventos. Rollback da aplicação **não significa descartar a auditoria recém-gerada**.
- Se Wazuh não receber evento sintético: app pode ter persistência local, mas o critério de coleta permanece **FAIL/pendente**. Não declarar Wazuh E2E por simples existência de agent ativo.
- Nenhuma credencial, key, cert, token, private key, conteúdo de `audit.log` ou `docker inspect` bruto deve integrar PR/evidências compartilhadas.

**Aceite do PR:** revisão docente/suporte, validação de Compose de dez arquivos e segurança de diretórios, política Wazuh operacional, estratégia de rotação, autorização para dados de auditoria, plano rollback completo e reteste E2E. **Sem merge/deploy até satisfazer esses gates.**
