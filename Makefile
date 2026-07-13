SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
MAKEFLAGS += --no-builtin-rules

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CHEZMOI_SOURCE := $(REPO_ROOT)/chezmoi
CHEZMOI_CONFIG_DIR := $(HOME)/.config/chezmoi
CHEZMOI_CONFIG := $(CHEZMOI_CONFIG_DIR)/chezmoi.toml
CHEZMOI_KEY := $(CHEZMOI_CONFIG_DIR)/key.txt
CHEZMOI_ENCRYPTED_KEY := $(CHEZMOI_SOURCE)/key.txt.age
CHEZMOI_DATA_DIR := $(CHEZMOI_SOURCE)/.chezmoidata
CHEZMOI_DATA_FILE := $(CHEZMOI_DATA_DIR)/secrets.yaml
CHEZMOI_BIN ?= $(shell $(REPO_ROOT)/bootstrap/install-chezmoi.sh)

CACHE_DIR ?= $(HOME)/.cache/dotfiles/secrets
STAGE_HOME := $(CACHE_DIR)/stage-home
DECRYPT_HOME ?= $(CACHE_DIR)/decrypted-home

BUNDLES := ssh gnupg
BUNDLE ?=
IMPORT_GPG ?= 0
GPG_KEY_IDS ?=
GPG_EXPORT_ROOT := .local/share/dotfiles/gnupg
GPG_CONFIG_FILES := gpg.conf gpg-agent.conf dirmngr.conf scdaemon.conf sshcontrol

all: help

##@ Secrets

.PHONY: age-init
age-init: ## Generate the repo age identity, recipient metadata, and local chezmoi config
	@mkdir -p "$(CHEZMOI_CONFIG_DIR)" "$(CHEZMOI_DATA_DIR)"
	@if [ -f "$(CHEZMOI_CONFIG)" ] && ! grep -Fq 'managed by /Users/teo/dotfiles/Makefile' "$(CHEZMOI_CONFIG)"; then \
		echo "Refusing to overwrite existing $(CHEZMOI_CONFIG) without the dotfiles marker" >&2; \
		exit 1; \
	fi
	@tmp_key="$$(mktemp)"; \
	trap 'rm -f "$$tmp_key"' EXIT; \
	recipient="$$( "$(CHEZMOI_BIN)" age-keygen --output "$$tmp_key" 2>&1 | awk '/^Public key:/ { print $$3 }' )"; \
	if [ -z "$$recipient" ]; then \
		echo "Failed to capture age recipient from chezmoi age-keygen" >&2; \
		exit 1; \
	fi; \
	install -m 600 "$$tmp_key" "$(CHEZMOI_KEY)"; \
	"$(CHEZMOI_BIN)" age encrypt --passphrase --output "$(CHEZMOI_ENCRYPTED_KEY)" "$$tmp_key"; \
	printf '%s\n' \
		'secrets:' \
		"  ageRecipient: $$recipient" \
		> "$(CHEZMOI_DATA_FILE)"; \
	printf '%s\n' \
		'# managed by /Users/teo/dotfiles/Makefile' \
		'encryption = "age"' \
		'[age]' \
		'    identity = "$(CHEZMOI_KEY)"' \
		"    recipient = \"$$recipient\"" \
		> "$(CHEZMOI_CONFIG)"
	@printf 'Initialized age recipient: %s\n' "$$(awk -F': ' '/ageRecipient:/ { print $$2 }' "$(CHEZMOI_DATA_FILE)")"

.PHONY: age-unlock
age-unlock: ## Decrypt key.txt.age into ~/.config/chezmoi/key.txt and refresh local chezmoi config
	@mkdir -p "$(CHEZMOI_CONFIG_DIR)"
	@if [ ! -s "$(CHEZMOI_ENCRYPTED_KEY)" ]; then \
		echo "Missing $(CHEZMOI_ENCRYPTED_KEY). Run 'make age-init' first." >&2; \
		exit 1; \
	fi
	@if [ ! -s "$(CHEZMOI_DATA_FILE)" ]; then \
		echo "Missing $(CHEZMOI_DATA_FILE). Run 'make age-init' first." >&2; \
		exit 1; \
	fi
	@"$(CHEZMOI_BIN)" age decrypt --output "$(CHEZMOI_KEY)" --passphrase "$(CHEZMOI_ENCRYPTED_KEY)"
	@chmod 600 "$(CHEZMOI_KEY)"
	@recipient="$$(awk -F': ' '/ageRecipient:/ { print $$2 }' "$(CHEZMOI_DATA_FILE)" | tail -n 1)"; \
	if [ -z "$$recipient" ]; then \
		echo "ageRecipient was empty in $(CHEZMOI_DATA_FILE)" >&2; \
		exit 1; \
	fi; \
	printf '%s\n' \
		'# managed by /Users/teo/dotfiles/Makefile' \
		'encryption = "age"' \
		'[age]' \
		'    identity = "$(CHEZMOI_KEY)"' \
		"    recipient = \"$$recipient\"" \
		> "$(CHEZMOI_CONFIG)"

.PHONY: encrypt
encrypt: ## Encrypt all bundles or specific ones with BUNDLE=ssh,gnupg
ifeq ($(BUNDLE),)
	@for bundle in $(BUNDLES); do \
		$(MAKE) encrypt-one BUNDLE=$$bundle; \
	done
else
	@for bundle in $$(echo "$(BUNDLE)" | tr ',' ' '); do \
		$(MAKE) encrypt-one BUNDLE=$$bundle; \
	done
endif

.PHONY: encrypt-one
encrypt-one: assert-age-ready ## Stage a single bundle and re-add it to chezmoi as encrypted files
	@rm -rf "$(STAGE_HOME)"
	@mkdir -p "$(STAGE_HOME)"
	@case "$(BUNDLE)" in \
		ssh) \
			src="$(HOME)/.ssh"; \
			dst="$(STAGE_HOME)/.ssh"; \
			if [ ! -d "$$src" ]; then \
				echo "Missing $$src" >&2; \
				exit 1; \
			fi; \
			mkdir -p "$$dst"; \
			find "$$src" -maxdepth 1 -type f \
				\( -name 'config' -o -name 'allowed_signers' -o -name 'authorized_keys' -o -name 'id_*' -o -name '*.pub' -o -name '*.pem' -o -name '*.crt' -o -name '*.cer' -o -name '*.p12' -o -name '*.asc' \) \
				! -name 'known_hosts*' \
				-print | while IFS= read -r file; do \
					install -m 600 "$$file" "$$dst/$$(basename "$$file")"; \
				done; \
			managed_paths="$$(cd "$(STAGE_HOME)" && find .ssh -type f | sort)"; \
			;; \
		gnupg) \
			src_gnupg="$${GNUPGHOME:-$(HOME)/.gnupg}"; \
			dst_gnupg="$(STAGE_HOME)/.gnupg"; \
			export_root="$(STAGE_HOME)/$(GPG_EXPORT_ROOT)"; \
			if ! command -v gpg >/dev/null 2>&1; then \
				echo "gpg is required for BUNDLE=gnupg" >&2; \
				exit 1; \
			fi; \
			mkdir -p "$$dst_gnupg" "$$export_root"; \
			for file in $(GPG_CONFIG_FILES); do \
				if [ -f "$$src_gnupg/$$file" ]; then \
					install -m 600 "$$src_gnupg/$$file" "$$dst_gnupg/$$file"; \
				fi; \
			done; \
			if [ -d "$$src_gnupg/openpgp-revocs.d" ]; then \
				find "$$src_gnupg/openpgp-revocs.d" -type f -name '*.rev' -print | while IFS= read -r file; do \
					install -Dm600 "$$file" "$$dst_gnupg/openpgp-revocs.d/$$(basename "$$file")"; \
				done; \
			fi; \
			export_args=""; \
			if [ -n "$(GPG_KEY_IDS)" ]; then \
				export_args="$(GPG_KEY_IDS)"; \
			fi; \
			GNUPGHOME="$$src_gnupg" gpg --batch --yes --armor --export $$export_args > "$$export_root/public.asc"; \
			GNUPGHOME="$$src_gnupg" gpg --batch --yes --armor --export-secret-keys $$export_args > "$$export_root/secret.asc"; \
			GNUPGHOME="$$src_gnupg" gpg --export-ownertrust > "$$export_root/ownertrust.txt"; \
			chmod 600 "$$export_root/"*; \
			managed_paths="$$(cd "$(STAGE_HOME)" && { find .gnupg -type f 2>/dev/null; find $(GPG_EXPORT_ROOT) -type f 2>/dev/null; } | sort)"; \
			;; \
		*) \
			echo "Error: Unknown BUNDLE '$(BUNDLE)'" >&2; \
			exit 1; \
			;; \
	esac; \
	if [ -z "$$managed_paths" ]; then \
		echo "No files were staged for $(BUNDLE)" >&2; \
		exit 1; \
	fi; \
	printf '%s\n' "$$managed_paths" | while IFS= read -r relpath; do \
		[ -n "$$relpath" ] || continue; \
		"$(CHEZMOI_BIN)" --config "$(CHEZMOI_CONFIG)" add --source "$(CHEZMOI_SOURCE)" --destination "$(STAGE_HOME)" --encrypt --force "$(STAGE_HOME)/$$relpath"; \
	done

.PHONY: decrypt
decrypt: ## Decrypt bundles into DECRYPT_HOME (default: ~/.cache/dotfiles/secrets/decrypted-home)
ifeq ($(BUNDLE),)
	@for bundle in $(BUNDLES); do \
		$(MAKE) decrypt-one BUNDLE=$$bundle; \
	done
else
	@for bundle in $$(echo "$(BUNDLE)" | tr ',' ' '); do \
		$(MAKE) decrypt-one BUNDLE=$$bundle; \
	done
endif

.PHONY: decrypt-one
decrypt-one: assert-age-ready ## Materialize a single bundle into DECRYPT_HOME; use IMPORT_GPG=1 for key import
	@mkdir -p "$(DECRYPT_HOME)"
	@case "$(BUNDLE)" in \
		ssh) \
			targets=".ssh"; \
			;; \
		gnupg) \
			targets=".gnupg $(GPG_EXPORT_ROOT)"; \
			;; \
		*) \
			echo "Error: Unknown BUNDLE '$(BUNDLE)'" >&2; \
			exit 1; \
			;; \
	esac; \
	HOME="$(DECRYPT_HOME)" USER="$(USER)" \
	"$(CHEZMOI_BIN)" --config "$(CHEZMOI_CONFIG)" apply --force --init --no-tty --exclude=scripts --source "$(CHEZMOI_SOURCE)" --destination "$(DECRYPT_HOME)" $$targets; \
	if [ "$(BUNDLE)" = "gnupg" ] && [ "$(IMPORT_GPG)" = "1" ]; then \
		if ! command -v gpg >/dev/null 2>&1; then \
			echo "gpg is required for IMPORT_GPG=1" >&2; \
			exit 1; \
		fi; \
		export_dir="$(DECRYPT_HOME)/$(GPG_EXPORT_ROOT)"; \
		gnupghome="$(DECRYPT_HOME)/.gnupg"; \
		mkdir -p "$$gnupghome"; \
		chmod 700 "$$gnupghome"; \
		if [ -f "$$export_dir/public.asc" ]; then \
			GNUPGHOME="$$gnupghome" gpg --batch --yes --import "$$export_dir/public.asc"; \
		fi; \
		if [ -f "$$export_dir/secret.asc" ]; then \
			GNUPGHOME="$$gnupghome" gpg --batch --yes --pinentry-mode loopback --import "$$export_dir/secret.asc" || \
			GNUPGHOME="$$gnupghome" gpg --batch --yes --import "$$export_dir/secret.asc"; \
		fi; \
		if [ -f "$$export_dir/ownertrust.txt" ]; then \
			GNUPGHOME="$$gnupghome" gpg --import-ownertrust "$$export_dir/ownertrust.txt"; \
		fi; \
	fi

.PHONY: clean-secrets-cache
clean-secrets-cache: ## Remove local staging and decrypted secret work directories
	@rm -rf "$(CACHE_DIR)"

.PHONY: assert-age-ready
assert-age-ready:
	@if [ ! -x "$(CHEZMOI_BIN)" ]; then \
		echo "chezmoi was not found. bootstrap/install-chezmoi.sh could not resolve it." >&2; \
		exit 1; \
	fi
	@if [ ! -s "$(CHEZMOI_ENCRYPTED_KEY)" ] || [ ! -s "$(CHEZMOI_DATA_FILE)" ]; then \
		echo "Encryption is not initialized. Run 'make age-init' first." >&2; \
		exit 1; \
	fi
	@if [ ! -s "$(CHEZMOI_KEY)" ] || [ ! -s "$(CHEZMOI_CONFIG)" ]; then \
		echo "Local chezmoi age config is missing. Run 'make age-unlock' first." >&2; \
		exit 1; \
	fi

##@ Help

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"; section = ""} \
	/^[a-zA-Z0-9_.-]+:.*##/ { \
		if (section != "") printf "\n\033[1m%s\033[0m\n", section; \
		section = ""; \
		printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2; next \
	} \
	/^##@/ { section = substr($$0, 5); next }' $(MAKEFILE_LIST)
	@printf "\n\033[1mAvailable BUNDLES:\033[0m\n"
	@for bundle in $(BUNDLES); do \
		printf "  \033[36m%s\033[0m\n" "$$bundle"; \
	done
	@printf "\n\033[1mExamples:\033[0m\n"
	@printf "  \033[36mmake age-init\033[0m\n"
	@printf "  \033[36mmake encrypt BUNDLE=ssh\033[0m\n"
	@printf "  \033[36mmake encrypt BUNDLE=gnupg GPG_KEY_IDS='E8D3009C6341BDEAF038009685AB6867E2147DDA'\033[0m\n"
	@printf "  \033[36mmake decrypt BUNDLE=gnupg IMPORT_GPG=1 DECRYPT_HOME=\$$HOME\033[0m\n"
