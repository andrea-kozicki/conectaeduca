# ConectaEduca — checkpoint de 30/10/2026 (BRT)

## Confirmado
- Connector Twingate na EP125: conforme evidência anterior da sessão, contêiner conectaeduca-dmz-01 operacional, Controller/Relay conectados; curl do bridge para HTTPS 192.168.6.34:443 retornou HTTP 200 com validação TLS desabilitada (NÃO comprova confiança de certificado nem acesso do cliente externo).
- Resource no painel: ConectaEducaAPP -> 192.168.6.34 TCP/443. Acesso de usuário final ainda NÃO validado.
- openSUSE Tumbleweed pessoal: FortiClient 7.4.3.5411 ativo, NetworkManager ativo, systemd-resolved inativo; /etc/resolv.conf regular com DNS local. Bibliotecas ELF libcryptsetup, libdbus, libcurl, libnl presentes.
- RPM twingate-latest 2026.302.7126-1 x86_64: SHA-256 f2ff3881759117f2af9f649a7c11300b6b0504ea41af3c2a5c18bf5e62e96855 conferiu em dois downloads; pacote sem assinatura RPM verificável. O zypper --dry-run recusou dependência nominal libcurl; usuária cancelou. Nenhuma instalação efetuada.
- Acesso às VMs via portal institucional/Guacamole exige FortiClient. A aplicação DMZ é recurso distinto: poderá ser acessada por cliente Twingate externo apenas após autenticação/autorização e E2E positivo.

## Retomar em 31/10 — prioridade P0
1. Decidir adaptação controlada do RPM para openSUSE sem --nodeps/--force; preferir teste do pacote adaptado em ambiente descartável antes de instalação no host. Validar procedência/autenticidade do pacote e scripts systemd/DNS. NÃO modificar FortiClient ou DNS/rotas às cegas.
2. Com cliente Twingate funcional, desligar FortiClient SOMENTE quando não depender do Guacamole, autenticar no tenant e testar https://192.168.6.34 com usuário autorizado; registrar TLS, HTTP, horário, identidade/grupo sem credenciais.
3. Teste negativo: usuário sem permissão não acessa recurso; testar alcance negado da EP126 (192.168.6.50) e serviços administrativos conforme escopo autorizado, sem confundir bloqueio de rede com RBAC PHP.
4. Verificar se acesso público preexistente à aplicação permanece e registrar risco residual; não alterar pfSense/WAF sem autorização.
5. Comparar evidências dos sete PAs e atualizar diário oficial EP125/EP126 após acesso às VMs. Registrar aqui que os diários locais NÃO foram editados nesta sessão, por falta de acesso direto às VMs.

## GitHub
- PR #213 permanece DRAFT; não fazer merge até revisão, testes positivo/negativo e política de exposição.
- PRs #205/#206/#207 permanecem em revisão/validação; não promover apenas por CI verde.
- Nenhuma alteração de runtime/VM nesta etapa.