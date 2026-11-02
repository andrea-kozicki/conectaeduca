# ConectaEduca — ZT-08: consolidado Twingate / portal EP125 / Wazuh EP126

**Data:** 02/11/2026 (BRT)  
**Natureza:** evidências de execução fornecidas pela operadora (terminal e capturas), não reexecução independente; nenhuma VM ou regra pfSense foi modificada nesta consolidação.  
**Documento ilustrado:** `ConectaEduca_Relatorio_Consolidado_ZeroTrust_ZT08_2026-11-02_v1.docx` entregue privadamente com **8 prints sanitizados**, sem upload de MFA/QR/URLs efêmeras ao GitHub.

## Resumo executivo

| Componente | Aceite delimitado | Evidência / limite |
|---|---|---|
| ConectaEducaAPP EP125 / Twingate sem FortiClient | **PASS** | Operadora confirmou FortiClient desconectado. `twingate status=online`, rota `192.168.6.34 dev sdwan0 src 100.96.0.2`, `curl -q --noproxy '*'` `HTTP=200 TLS_VERIFY=0 CURL_RC=0`; Firefox perfil `ConectaEduca-Lab` mostrou home sem alerta após importar CA pública interna. |
| CA da aplicação EP125 no Firefox | **PASS funcional do navegador** | Inicialmente `SEC_ERROR_UNKNOWN_ISSUER`; CA interna encontrada no trust store openSUSE, exportada, conferida `CA:TRUE`, importada no perfil de laboratório. Nenhuma exceção de site por `-k`/botão “Prosseguir”. |
| Resource Wazuh no Twingate antes do MFA | **PENDING / timeout** | `twingate resources`: `ConectaEduca — Wazuh Dashboard` status `Pending`; alias `wazuh.dashboard` resolvido em `100.99.142.20` (IP virtual transitório); `curl --cacert` `HTTP=000 CURL_RC=28`, timeout ~5 s. `TLS_VERIFY=0` **não confirma handshake** nesse teste. |
| MFA do Twingate para Wazuh | **PASS** | `twingate auth 'ConectaEduca — Wazuh Dashboard'`; navegador mostrou desafio MFA e o terminal registrou `Authentication successful`. URL e QR de autenticação omitidos do relatório. |
| Acesso à interface Wazuh EP126 | **PASS apenas página de login** | Firefox carregou `https://wazuh.dashboard/app/login` com tela de autenticação do Wazuh. Não houve prova de login com usuário/senha do Wazuh, alertas internos ou teste de identidade não autorizada. |
| Segregação por identidade Pentest B | **PENDENTE** | Criar usuário Twingate não-admin com Resource ConectaEducaAPP, sem Wazuh; provar allow/deny sem acesso direto alternativo. |
| PA-02 microsegmentação e exposição direta | **PENDENTE** | A rota pelo Twingate não prova isolamento contra host Docker/bridge nem garante que portal público esteja privado. |

## Detalhes verificáveis da CA EP125

- Servidor: `https://192.168.6.34/`; certificado Subject `CN=conectaeduca.local`; Issuer `CN=ConectaEduca Lab Root CA`; SAN `DNS:conectaeduca.local`, `IP:192.168.6.34`.
- Fingerprint SHA-256 do **certificado servidor**: `89:35:0A:EC:31:19:C0:C9:AB:82:51:04:45:78:11:56:04:46:94:B3:DD:63:6F:75:C2:37:55:F4:74:0A:AF:17`.
- CA pública do laboratório, `CA:TRUE`, pathlen 0: fingerprint SHA-256 `C4:CF:23:F1:1F:3C:2D:71:13:4D:4F:63:61:D3:6B:1F:E1:F2:D9:72:E6:37:9C:E7:42:9F:F7:FD:18:48:59:D4`.
- A imagem da aplicação no Firefox sem aviso foi fornecida no chat; screenshot incluída **somente na cópia DOCX sanitizada**.

## Resource Wazuh / CA própria EP126

- Resource `ConectaEduca — Wazuh Dashboard`, endereço de destino `127.0.0.1:443` no Connector EP126, alias `wazuh.dashboard`; esse loopback **não** é o loopback do openSUSE. Grupo `CE-SOC-OPERACAO`, política MFA.
- CA Wazuh no openSUSE em `~/Downloads/root-ca.pem`; SHA-256 do arquivo `68fa6e5bcdeaca4f4759932619887638594f26aff5b2269a7b833db49c498065`, igual à evidência de 31/10.
- `ZT-07.20` de 31/10 havia comprovado `curl --cacert` com HTTP 302/TLS_VERIFY=0/CURL_RC=0. O novo teste de 02/11 **antes** do MFA deu timeout; depois do MFA, houve sucesso no navegador. Não atribuir o sucesso pós-MFA automaticamente à CA da aplicação EP125, pois são autoridades distintas.

## Capturas ilustrativas anexadas ao DOCX privado

1. Estado inicial/reconexão do Twingate e Resources (QR/URL omitidos).
2. Firefox mostrando `SEC_ERROR_UNKNOWN_ISSUER` antes da correção.
3. Perfil `ConectaEduca-Lab` em uso (caminhos pessoais ocultados).
4. Mesmo erro de certificado no perfil antes da importação da CA.
5. Página inicial ConectaEducaAPP renderizada no Firefox.
6. Desafio MFA do Resource Wazuh (URL temporária excluída).
7. `twingate auth` com `Authentication successful` (QR/token excluídos).
8. Tela Wazuh `wazuh.dashboard/app/login`.

**Segurança:** nunca publicar capturas originais que revelem tokens MFA, URLs temporárias ou QR codes de autenticação. O arquivo Word incorpora cópias editadas; inclui SHA-256 originais e derivados para rastreabilidade local, mas **não** distribui capturas brutas.

## Próximos gates

1. Conta Twingate limitada e testes `allow` ConectaEducaAPP / `deny` Wazuh, sem FortiClient.
2. Login Wazuh sob conta autorizada e telemetria Twingate/Wazuh (sem credenciais).
3. Verificar se existe acesso direto ao portal fora da camada Twingate, de acordo com a decisão institucional público/privado; segregar endpoint administrativo.
4. Não confundir o resultado positivo da aplicação com encerramento de PA-02; aplicar correção WAF→Nginx de modo controlado e demonstrar bloqueio da bridge.
5. Não reinstalar Connectors saudáveis nem refazer inventário; preservar estado/rollback e freeze acadêmico previsto em 07/11.

**Situação acadêmica:** marco positivo de comunicação via Zero Trust e MFA por Resource. **Homologação total de Zero Trust e Pentest B continuam pendentes.** Referências: PR #213 (EP125), PR #214 (EP126/evidências), Trello ZT-06 / ZT-07.
