# RUNBOOK — Acesso ao Wazuh Dashboard por Twingate no openSUSE

**Projeto:** ConectaEduca — Experiência Criativa 8 • **Registro:** 01/11/2026 • **Gate:** ZT-07.25 • **Alvo:** `https://wazuh.dashboard/`  
**Operadora:** usuário autorizado do laboratório • **Dispositivo:** openSUSE pessoal • **Caminho:** Twingate Client → Resource privado Wazuh → Connector **institucional** na EP126 → Wazuh Dashboard no loopback do host  
**Status do gate:** **GUI HTTPS e tela de login Wazuh VISÍVEIS no Firefox** (evidência de captura enviada no chat em 01/11, arquivo `image(20261101-164804).png`); **login com usuário/senha do Wazuh, acesso negado por identidade não autorizada e correlação de logs NÃO demonstrados**. Não confundir autenticação MFA do Twingate com login da aplicação Wazuh.

> Este runbook recupera precisamente o caminho que funcionou no laboratório. A imagem original foi enviada no chat; **não foi anexada à árvore Git** por este registro. Nenhuma credencial, QR code, código MFA, token de Connector ou chave privada pode entrar em evidência pública.

## A. Retomada rápida — toda vez que for acessar o laboratório

**Executar no terminal do openSUSE, sem `sudo`. NÃO executar na EP126.**

```bash
# 1. Verificar se o Client local está rodando
twingate status

# Se aparecer "not-running", iniciar o CLIENT:
twingate start
twingate status

# 2. Listar Resources da identidade (atenção ao AUTH STATUS individual)
twingate resources

# 3. Apenas se o Wazuh estiver "Pending" ou for exigida autenticação adicional:
twingate auth 'ConectaEduca — Wazuh Dashboard'
# Completar o MFA no navegador aberto pelo Client; esperar "Authentication successful".

# 4. Confirmar permissão atual do Resource e DNS privado
twingate resources
getent ahostsv4 wazuh.dashboard

# 5. Verificar HTTPS/TLS de forma NÃO invasiva, sem -k
curl --noproxy '*' \
  --cacert "$HOME/Downloads/root-ca.pem" \
  --silent --show-error \
  --output /dev/null \
  --connect-timeout 8 --max-time 20 \
  --write-out 'HTTP=%{http_code} IP=%{remote_ip} TLS_VERIFY=%{ssl_verify_result}\n' \
  https://wazuh.dashboard/
echo "CURL_RC=$?"
```

**Aceite de transporte:** `twingate status` online; Wazuh NÃO Pending; `getent` resolve endereço virtual Twingate `100.x.x.x`; `curl` retorna `HTTP=302` ou outra resposta HTTPS esperada do serviço (observada: `302`), `TLS_VERIFY=0`, `CURL_RC=0`. O IP virtual pode variar entre sessões — **não fixar IP em hosts, Firefox ou scripts**.

Depois, no Firefox **perfil isolado `ConectaEduca-Lab`**, abrir **`https://wazuh.dashboard/`**. Tela observada em 01/11: logo Wazuh e formulário `Username`/`Password`/`Log in`; a rota exibida no navegador era `wazuh.dashboard/app/login?`. **Não afirmar que credenciais Wazuh foram aceitas** com base nessa tela.

### O atalho mental para não repetir três horas de diagnóstico

1. `not-running` → **`twingate start`**, não reinstalar certificado.
2. Resource Wazuh `Pending` → **`twingate auth 'ConectaEduca — Wazuh Dashboard'`**, não alterar pfSense.
3. Status autorizada + DNS resolvido → só então testar `curl --cacert` e abrir Firefox.

**Importante:** login no portal do Twingate *não inicia necessariamente o Client Linux*. `ConectaEducaAPP` (EP125) e `ConectaEduca — Wazuh Dashboard` têm **status de autenticação independente**: em 01/11 um estava `Auth expires in 4 days` e o Wazuh `Pending`. Após iniciar o Client, a falha do Wazuh era de **MFA específica desse Resource**, não de disponibilidade do Connector.

## B. Preparação única do Firefox (não repetir em cada sessão)

1. Abrir `about:profiles`; criar perfil separado **`ConectaEduca-Lab`**; iniciar o perfil numa nova janela. Preservar o perfil pessoal como padrão.
2. No perfil **ConectaEduca-Lab**: `about:preferences#privacy` → **Certificados / Ver certificados / Autoridades / Importar** → selecionar `/home/andrea/Downloads/root-ca.pem`. Confiar na CA para **identificar sites**. **Não importar no perfil pessoal, nem no sistema inteiro, nem confiar em chaves privadas.**
3. Se houver problema de resolução exclusivo do navegador, conferir **DNS sobre HTTPS** (*DoH*) em `about:preferences#privacy`; no caso de 01/11 **já estava desativado por padrão**, portanto **não era a causa** da falha. Conferir também configurações de proxy do perfil se `curl` funcionar e Firefox não.
4. A CA pública transferida da EP126 foi verificada no cliente em 01/11 com:
   ```bash
   sha256sum "$HOME/Downloads/root-ca.pem"
   ```
   **SHA-256 esperado (arquivo completo):** `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`. Valor **confirmado** pela operadora no openSUSE, correspondendo ao arquivo público examinado na EP126.
5. Usar `https://wazuh.dashboard/` — não `http://`, nem `127.0.0.1` do laptop (que aponta para o próprio laptop).

**Cuidado:** a CA Wazuh é emissora de certificados, portanto restringir confiança ao perfil de laboratório; proteger a cópia local e não distribuir. A segurança do TLS depende da integridade do arquivo CA e do nome `wazuh.dashboard` coberto pelo certificado.

## C. Tabela de decisão baseada nos erros reais

| Evidência / sintoma | Causa comprovada ou hipótese | Próxima ação mínima |
|---|---|---|
| `twingate status` = `not-running`; `getent` sem IP; `curl (6) Could not resolve host`; Firefox “Servidor não encontrado” | **Comprovado em 01/11:** Client local desligado; login em portal não o iniciou | `twingate start`, `twingate status`, `twingate resources`; **não** modificar Wazuh/CA/pfSense |
| `getent` retorna IP virtual `100.x`; Wazuh `Pending`; `curl (28) Connection timed out` | **Comprovado em 01/11:** Wazuh exigia autenticação adicional MFA | `twingate auth 'ConectaEduca — Wazuh Dashboard'`; MFA; depois `twingate resources` e `curl` |
| `curl (60)` / `TLS_VERIFY=20` quando não se usa CA local | CA Wazuh não é reconhecida pelo cliente, verificação TLS falhou | Validar hash CA e repetir somente com `--cacert "$HOME/Downloads/root-ca.pem"`; **não** usar `-k/--insecure` como aceite |
| `curl` funciona mas Firefox não | Divergência entre configuração do navegador e do sistema | Verificar perfil correto, trust store do perfil, DoH/proxy, e Twingate em execução; não presumir que DoH era a causa em 01/11 |
| Firefox mostra formulário `Username / Password / Log in` sem alerta TLS | **ZT-07.25 PASS para acesso à GUI de login** | Registrar evidência; realizar login da aplicação com conta de teste autorizada em gate separado |
| Wazuh login aceita credenciais, mas outra identidade também vê o Resource | Não concluído / risco de política | Fazer teste allow/deny autorizado com identidade sem grupo, examinar logs e RBAC; não remover acessos institucionais sem aval |

**Não reiniciar** o antigo Connector Docker pessoal `conectaeduca-interna-01` no openSUSE: este não é o Twingate Client e poderia provocar conflito de roteamento/Resource loopback. Na EP126 o Connector institucional `conectaeduca-twingate-connector` fica na rede host e encaminha o Wazuh publicado em `127.0.0.1:443`. Connectors não são instalados em cada contêiner do Wazuh.

## D. Cronologia compacta comprovada — 01/11/2026

| Etapa | Evidência disponível | Conclusão |
|---|---|---|
| EP126 ZT-07.22 | Connector `healthy` / Wazuh `healthy`; HTTPS EP126 local `HTTP=302 TLS_VERIFY=0 CURL_RC=0` | Backend e TLS local operacionais |
| openSUSE CA | Hash idêntico ao certificado público validado na EP126 | Transferência íntegra |
| Firefox falhou | Tela “Servidor não encontrado” no perfil de laboratório | Sintoma observado, **não** problema de CA |
| openSUSE Client | `not-running`; `getent` vazio; `curl (6)` | Causa da falha DNS confirmada |
| Após iniciar Client | Resource ConectaEducaAPP autorizado, Wazuh `Pending`; DNS virtual `100.110.213.17`; `curl (28)` | Client recuperado, bloqueio de sessão MFA do Wazuh |
| Após autenticar Wazuh | Captura subsequente mostra formulário de login Wazuh em Firefox, endereço `wazuh.dashboard/app/login?`, ícone de HTTPS | **ZT-07.25: GUI HTTPS acessível**. A saída textual pós-MFA desta etapa não foi anexada; a captura prova o resultado visual, não os passos intermediários de autenticação nem o login da aplicação |

**Integração atual ainda parcialmente homologada:** HTTPS remoto com CA = PASS (31/10); browser GUI/login form = PASS (01/11); login Wazuh com usuário autorizado = **PENDENTE**; deny por identidade/grupo = **PENDENTE**; logs correlacionados + reconciliação Git/runtime/rollback + diário local = **PENDENTE**. Não marcar a ZT-07 como DONE prematuramente.

## E. Links e continuidade

- Relatório técnico consolidado: [ZT EP126 e pendências](../evidencias/CONSOLIDADO-ZT-EP126-20261031-TESTES-E-PENDENCIAS.md)
- Diário operacional espelhado: [registros EP126 / ZT-07](../evidencias/DIARIO-OPERACIONAL-20261031-EP126-ZT06-GA09.md)
- Trello: [ZT-07 — Resource Wazuh](https://trello.com/c/2lanN6ZC), [ZT-06 — Connector](https://trello.com/c/Rdadjeud)
- GitHub [PR #214](https://github.com/andrea-kozicki/conectaeduca/pull/214), documentação em draft, ainda **não mergeada**.

**Escopo de atuação do runbook:** comandos de leitura e autenticação interativa de Client; nenhum `sudo`, `git pull`, `docker restart`, `docker compose up`, alteração de ACL/host network/firewall ou instalação de Connector.
