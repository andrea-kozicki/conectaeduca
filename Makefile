# Makefile portável para provisionamento e verificação das chaves RSA do ConectaEduca.
#
# IMPORTANTE:
# - As chaves fazem parte do material criptográfico persistente da aplicação.
# - "make keys" NÃO sobrescreve um par existente.
# - "make clean" NÃO remove chaves persistentes.
# - Destruição intencional exige confirmação explícita em "make destroy-keys".
#
# Compatível principalmente com Linux, macOS, WSL e Git Bash.

KEYS_DIR ?= storage/keys
PRIVATE_KEY_PKCS1 ?= $(KEYS_DIR)/private.pem
PUBLIC_KEY ?= $(KEYS_DIR)/public.pem
TEMP_PUB_KEY ?= $(KEYS_DIR)/.temp_check_public.pem
TEMP_PRIVATE_KEY ?= $(KEYS_DIR)/.private.pem.tmp
TEMP_PUBLIC_KEY ?= $(KEYS_DIR)/.public.pem.tmp

OWNER ?= $(shell id -un 2>/dev/null || echo "")
GROUP ?= $(shell id -gn 2>/dev/null || echo "")

OPENSSL ?= openssl
CMP ?= cmp
RM ?= rm -f
MKDIR_P ?= mkdir -p
MV ?= mv

HASH_CMD := $(shell if command -v shasum >/dev/null 2>&1; then \
	echo "shasum -a 256"; \
elif command -v sha256sum >/dev/null 2>&1; then \
	echo "sha256sum"; \
else \
	echo ""; \
fi)

HAS_CHMOD := $(shell command -v chmod >/dev/null 2>&1 && echo yes || echo no)
HAS_CHOWN := $(shell command -v chown >/dev/null 2>&1 && echo yes || echo no)

.PHONY: help setup check-keys keys hash fix-perms fix-owner check clean destroy-keys

help:
	@echo "Alvos disponíveis:"
	@echo "  make setup                         -> gera o par somente se nenhuma chave existir"
	@echo "  make check-keys                    -> verifica existência e integridade do par"
	@echo "  make keys                          -> gera um NOVO par; recusa sobrescrever chaves existentes"
	@echo "  make check                         -> valida se a pública corresponde à privada"
	@echo "  make hash                          -> mostra hashes SHA-256 das chaves"
	@echo "  make fix-perms                     -> aplica permissões seguras, se suportado"
	@echo "  make fix-owner OWNER=x GROUP=y     -> ajusta dono/grupo, se suportado"
	@echo "  make clean                         -> remove somente temporários; preserva as chaves"
	@echo "  make destroy-keys CONFIRM_DESTROY_KEYS=SIM"
	@echo "                                     -> DESTRÓI o par persistente de forma explícita"

setup:
	@if [ -f "$(PRIVATE_KEY_PKCS1)" ] && [ -f "$(PUBLIC_KEY)" ]; then \
		echo "✅ Chaves RSA já existem em $(KEYS_DIR). Validando..."; \
		$(MAKE) check; \
	elif [ -e "$(PRIVATE_KEY_PKCS1)" ] || [ -e "$(PUBLIC_KEY)" ]; then \
		echo "❌ Estado inseguro: somente uma das chaves existe em $(KEYS_DIR)."; \
		echo "   Não haverá geração automática para evitar perda de material criptográfico."; \
		exit 1; \
	else \
		echo "⚠️ Chaves não encontradas. Gerando um novo par..."; \
		$(MAKE) keys; \
	fi

check-keys:
	@if [ -f "$(PRIVATE_KEY_PKCS1)" ] && [ -f "$(PUBLIC_KEY)" ]; then \
		echo "✅ Chaves encontradas:"; \
		ls -l "$(PRIVATE_KEY_PKCS1)" "$(PUBLIC_KEY)" 2>/dev/null || true; \
		$(MAKE) check; \
	elif [ -e "$(PRIVATE_KEY_PKCS1)" ] || [ -e "$(PUBLIC_KEY)" ]; then \
		echo "❌ Par incompleto: existe apenas uma das chaves."; \
		exit 1; \
	else \
		echo "❌ Chaves não encontradas em $(KEYS_DIR)"; \
		exit 1; \
	fi

keys:
	@if [ -e "$(PRIVATE_KEY_PKCS1)" ] || [ -e "$(PUBLIC_KEY)" ]; then \
		echo "❌ Geração recusada: já existe material criptográfico em $(KEYS_DIR)."; \
		echo "   Use 'make check-keys' para validar o par existente."; \
		echo "   Rotação de chaves exige recriptografia dos dados e não é feita por este alvo."; \
		exit 1; \
	fi
	@echo "🔐 Gerando novo par RSA sem sobrescrever chaves existentes..."
	@$(MKDIR_P) "$(KEYS_DIR)"
	@$(RM) "$(TEMP_PRIVATE_KEY)" "$(TEMP_PUBLIC_KEY)"
	@set -e; \
		trap '$(RM) "$(TEMP_PRIVATE_KEY)" "$(TEMP_PUBLIC_KEY)"' EXIT HUP INT TERM; \
		$(OPENSSL) genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 | \
			$(OPENSSL) rsa -traditional -out "$(TEMP_PRIVATE_KEY)"; \
		$(OPENSSL) rsa -in "$(TEMP_PRIVATE_KEY)" -pubout -out "$(TEMP_PUBLIC_KEY)"; \
		$(MV) "$(TEMP_PRIVATE_KEY)" "$(PRIVATE_KEY_PKCS1)"; \
		$(MV) "$(TEMP_PUBLIC_KEY)" "$(PUBLIC_KEY)"; \
		trap - EXIT HUP INT TERM
	@$(MAKE) fix-perms
	@$(MAKE) hash
	@$(MAKE) check
	@echo "✅ Chaves geradas. Faça backup seguro da chave privada antes de armazenar dados cifrados."

hash:
	@echo "🧾 Hash das chaves:"
	@if [ -n "$(HASH_CMD)" ]; then \
		$(HASH_CMD) "$(PRIVATE_KEY_PKCS1)"; \
		$(HASH_CMD) "$(PUBLIC_KEY)"; \
	else \
		echo "⚠️ Nenhum comando de hash encontrado (shasum/sha256sum)."; \
	fi

fix-perms:
	@echo "🔧 Aplicando permissões seguras (se suportado)..."
	@if [ "$(HAS_CHMOD)" = "yes" ]; then \
		chmod 750 "$(KEYS_DIR)" 2>/dev/null || true; \
		chmod 640 "$(PRIVATE_KEY_PKCS1)" 2>/dev/null || true; \
		chmod 644 "$(PUBLIC_KEY)" 2>/dev/null || true; \
		echo "✅ Permissões aplicadas."; \
	else \
		echo "⚠️ chmod não disponível. Ignorando ajuste de permissões."; \
	fi

fix-owner:
	@echo "🔧 Ajustando dono/grupo para $(OWNER):$(GROUP) (se suportado)..."
	@if [ "$(HAS_CHOWN)" = "yes" ] && [ -n "$(OWNER)" ] && [ -n "$(GROUP)" ]; then \
		sudo chown "$(OWNER):$(GROUP)" "$(KEYS_DIR)" "$(PRIVATE_KEY_PKCS1)" "$(PUBLIC_KEY)" 2>/dev/null || true; \
		echo "✅ Dono/grupo ajustados."; \
	else \
		echo "⚠️ chown não disponível ou OWNER/GROUP não definidos. Ignorando."; \
	fi

check:
	@echo "🔍 Verificando se a pública corresponde à privada..."
	@if [ ! -f "$(PRIVATE_KEY_PKCS1)" ] || [ ! -f "$(PUBLIC_KEY)" ]; then \
		echo "❌ Par de chaves incompleto."; \
		exit 1; \
	fi
	@set -e; \
		trap '$(RM) "$(TEMP_PUB_KEY)"' EXIT HUP INT TERM; \
		$(OPENSSL) rsa -in "$(PRIVATE_KEY_PKCS1)" -pubout -out "$(TEMP_PUB_KEY)" 2>/dev/null; \
		$(CMP) --silent "$(TEMP_PUB_KEY)" "$(PUBLIC_KEY)"; \
		echo "✅ As chaves correspondem!"; \
		trap - EXIT HUP INT TERM; \
		$(RM) "$(TEMP_PUB_KEY)"

clean:
	@$(RM) "$(TEMP_PUB_KEY)" "$(TEMP_PRIVATE_KEY)" "$(TEMP_PUBLIC_KEY)"
	@echo "🧹 Temporários removidos. Chaves persistentes foram preservadas."

destroy-keys:
	@if [ "$(CONFIRM_DESTROY_KEYS)" != "SIM" ]; then \
		echo "❌ Operação recusada."; \
		echo "   A chave privada pode ser necessária para descriptografar dados existentes."; \
		echo "   Para destruir deliberadamente o par, execute:"; \
		echo "   make destroy-keys CONFIRM_DESTROY_KEYS=SIM"; \
		exit 1; \
	fi
	@$(RM) "$(PRIVATE_KEY_PKCS1)" "$(PUBLIC_KEY)" "$(TEMP_PUB_KEY)" "$(TEMP_PRIVATE_KEY)" "$(TEMP_PUBLIC_KEY)"
	@echo "⚠️ Par RSA destruído por solicitação explícita."
