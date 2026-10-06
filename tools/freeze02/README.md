# FREEZE-02 - scripts operacionais preparados

Branch de apoio: `prep/freeze02-fechamento-20261006`

Base exata: `c37bdce07a9ae71ceb1a1e0c8e0e1e2b51e112ce`

**Nao fazer merge desta branch antes do FREEZE-02 estar encerrado.**
Ela existe apenas para deixar os scripts de amanha prontos sem alterar a `main`,
o SHA candidato ou a evidencia Snyk ja validada.

Para copiar um script sem trocar de branch nem sujar o worktree:

```bash
cd /opt/conectaeduca
git fetch origin prep/freeze02-fechamento-20261006
git show origin/prep/freeze02-fechamento-20261006:tools/freeze02/10-ep125-rebuild-dmz.sh > ~/10-ep125-rebuild-dmz.sh
chmod +x ~/10-ep125-rebuild-dmz.sh
```

Repita o mesmo padrao para os demais arquivos.

Ordem prevista:

1. EP125: `10-ep125-rebuild-dmz.sh`
2. EP125: `20-ep125-validar-dmz.sh`
3. Smoke manual curto no navegador: login + MFA + RBAC, sem registrar senhas/TOTP
4. EP126: `30-ep126-checks-finais.sh`
5. EP126: revisar o drift de `.conectaeduca-storage-path.env` indicado pelo script
6. Em cada VM: `40-gerar-handoff.sh`
7. Depois: manifesto/pacote final e tag somente apos revisao de todos os PASS

Twingate permanece desligado ate o fim do Pentest A.
