# Makefile portável para geração e verificação de chaves RSA
# Compatível principalmente com Linux, macOS, WSL e Git Bash.
# Em ambientes diferentes, ajustes de permissões e dono/grupo são opcionais.

KEYS_DIR ?= keys
PRIVATE_KEY_PKCS1 ?= $(KEYS_DIR)/private.pem
PUBLIC_KEY ?= $(KEYS_DIR)/public.pem
TEMP_PUB_KEY ?= $(KEYS_DIR)/temp_check_public.pem

OWNER ?= $(shell id -un 2>/dev/null || echo "")
GROUP ?= $(shell id -gn 2>/dev/null || echo "")

OPENSSL ?= openssl
CMP ?= cmp
RM ?= rm -f
MKDIR_P ?= mkdir -p

HASH_CMD := $(shell if command -v shasum >/dev/null 2>&1; then \
	echo "shasum -a 256"; \
elif command -v sha256sum >/dev/null 2>&1; then \
	echo "sha256sum"; \
else \
	echo ""; \
fi)

HAS_CHMOD := $(shell command -v chmod >/dev/null 2>&1 && echo yes || echo no)
HAS_CHOWN := $(shell command -v chown >/dev/null 2>&1 && echo yes || echo no)

.PHONY: help setup check-keys keys hash fix-perms fix-owner check clean

help:
	@echo "Alvos disponíveis:"
	@echo "  make setup                     -> gera as chaves se necessário"
	@echo "  make check-keys                -> verifica se as chaves existem"
	@echo "  make keys                      -> gera/regenera o par RSA"
	@echo "  make check                     -> valida se a pública corresponde à privada"
	@echo "  make fix-perms                 -> aplica permissões seguras, se suportado"
	@echo "  make fix-owner OWNER=x GROUP=y -> ajusta dono/grupo, se suportado"
	@echo "  make clean                     -> remove as chaves"

setup:
	@if [ -f "$(PRIVATE_KEY_PKCS1)" ] && [ -f "$(PUBLIC_KEY)" ]; then \
		echo "✅ Chaves RSA já existem em $(KEYS_DIR)"; \
	else \
		echo "⚠️ Chaves não encontradas. Gerando..."; \
		$(MAKE) keys; \
	fi

check-keys:
	@if [ -f "$(PRIVATE_KEY_PKCS1)" ] && [ -f "$(PUBLIC_KEY)" ]; then \
		echo "✅ Chaves encontradas:"; \
		ls -l "$(PRIVATE_KEY_PKCS1)" "$(PUBLIC_KEY)" 2>/dev/null || true; \
	else \
		echo "❌ Chaves não encontradas em $(KEYS_DIR)"; \
		exit 1; \
	fi

keys:
	@echo "🔐 Gerando chave RSA..."
	@$(MKDIR_P) "$(KEYS_DIR)"
	@$(OPENSSL) genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 | \
		$(OPENSSL) rsa -traditional -out "$(PRIVATE_KEY_PKCS1)"
	@echo "📤 Gerando chave pública..."
	@$(OPENSSL) rsa -in "$(PRIVATE_KEY_PKCS1)" -pubout -out "$(PUBLIC_KEY)"
	@$(MAKE) fix-perms
	@$(MAKE) hash
	@$(MAKE) check
	@echo "✅ Chaves geradas."

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
	@$(OPENSSL) rsa -in "$(PRIVATE_KEY_PKCS1)" -pubout -out "$(TEMP_PUB_KEY)" 2>/dev/null
	@$(CMP) --silent "$(TEMP_PUB_KEY)" "$(PUBLIC_KEY)" && echo "✅ As chaves correspondem!" || \
		(echo "❌ As chaves não correspondem!"; exit 1)
	@$(RM) "$(TEMP_PUB_KEY)"

clean:
	@$(RM) "$(PRIVATE_KEY_PKCS1)" "$(PUBLIC_KEY)" "$(TEMP_PUB_KEY)"
	@echo "🧹 Chaves removidas."
