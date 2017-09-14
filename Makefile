MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_PATH := $(patsubst %/,%,$(dir $(MKFILE_PATH)))

DOCKER_USER := user
DOCKER_APP_HOME := /home/$(DOCKER_USER)
DOCKER_PROJECT_PATH := $(DOCKER_APP_HOME)/app

PROJECT_NAME ?= xcflushd
GITHUB ?= 3scale/$(PROJECT_NAME)

# GnuPG 2 and skopeo are needed
GPG ?= $(shell which gpg2 2> /dev/null)
SKOPEO ?= $(shell which skopeo 2> /dev/null)
CURL ?= $(shell which curl 2> /dev/null)
DOCKER ?= $(shell which docker 2> /dev/null)
TAG ?= $(shell git describe --dirty | sed -E -e "s/v([0-9]+.*)/\1/")

REGISTRY ?= registry.hub.docker.com
REPOSITORY ?= 3scale

# Alex's key until a Red Hat 3scale API Management Platform Signing Key becomes
# official.
KEY_ID ?= 0x1906BF9871FC70B4C3B1B33ADD8266DDCBFD2C6F
KEY_FILE_NAME ?= $(KEY_ID).asc
KEY_FILE_DIR ?= $(PROJECT_PATH)
KEY_FILE = $(KEY_FILE_DIR)/$(KEY_FILE_NAME)
TRUST_KEY_FILE ?= 0

DOCKER_REL ?= 1
DOCKER_VERSION = $(TAG)-$(DOCKER_REL)
DOCKER_BUILD_ARGS ?=
LOCAL_IMAGE = $(PROJECT_NAME):$(DOCKER_VERSION)
TARGET_IMAGE = $(REGISTRY)/$(REPOSITORY)/$(LOCAL_IMAGE)

MANIFEST ?= $(PROJECT_NAME)-image-$(DOCKER_VERSION).manifest
SIGNATURE ?= $(PROJECT_NAME)-image-$(DOCKER_VERSION).signature

TEST_CMD ?= script/test

VERIFY_DOCKERFILE = Dockerfile.verify
VERIFY_IMAGE = $(PROJECT_NAME):verify

BANNER_LINE = ******************************************************************
INFO_MARK = [II]
WARN_MARK = [WW]

DOCKER_VERIFY_RUN := $(DOCKER) run --rm --security-opt label:disable \
	-v $(PROJECT_PATH):/opt/app -v /var/run/docker.sock:/var/run/docker.sock \
	-ti $(VERIFY_IMAGE)
# Pass here all variables important for running the make instance inside Docker
DOCKER_VERIFY_MAKE = $(DOCKER_VERIFY_RUN) make \
			TAG=$(TAG) DOCKER_REL=$(DOCKER_REL) \
			TARGET_IMAGE=$(TARGET_IMAGE) MANIFEST=$(MANIFEST) \
			SIGNATURE=$(SIGNATURE) TRUST_KEY_FILE=$(TRUST_KEY_FILE) \
			KEY_ID=$(KEY_ID)

default: test

define pinfo
	@echo -e "\n$(BANNER_LINE)\n$(INFO_MARK) $(1)\n$(BANNER_LINE)"
endef

define pwarn
	@echo -e "\n$(WARN_MARK) $(1)\n"
endef

.PHONY: release
release:
	@if $$(which getsebool 2> /dev/null >&2); then \
		OFF=$$(getsebool domain_kernel_load_modules | sed -E -e "s/.*\s+(off)$$/\\1/"); \
		if test "x$${OFF}" = "xoff"; then \
		    echo "$(WARN_MARK) On SELinux module_request calls might be common, you might want to:"; \
	        echo "$(WARN_MARK) $$ sudo -- setsebool domain_kernel_load_modules=1"; \
		    sleep 5; \
		fi; \
	fi
	$(call pinfo,"Building $(PROJECT_NAME) $(TAG)...")
	@$(MAKE) --no-print-directory info build test tag
	$(call pinfo,"Publishing $(TARGET_IMAGE) in 10 secs")
	@sleep 10
	@$(MAKE) --no-print-directory push
	$(call pinfo,"Signing $(TARGET_IMAGE)...")
	@$(MAKE) --no-print-directory sign-docker
	$(call pinfo,"You can now upload $(SIGNATURE) to release page")

.PHONY: fetch-key
fetch-key:
	$(GPG) --recv-keys $(KEY_ID)

.PHONY: fetch-signature
fetch-signature:
	$(call pinfo,"Fetching signature for $(PROJECT_NAME) $(TAG)-$(DOCKER_REL)...")
	$(CURL) -L -O -s https://github.com/$(GITHUB)/releases/download/v$(TAG)/$(SIGNATURE)

.PHONY: info
info:
	@echo -e "\n" \
	"The following variables _can_ be modified:\n\n" \
	"* PROJECT_NAME = $(PROJECT_NAME)\n" \
	"* GITHUB = $(GITHUB)\n" \
	"* GPG = $(GPG)\n" \
	"* SKOPEO = $(SKOPEO)\n" \
	"* CURL = $(CURL)\n" \
	"* DOCKER = $(DOCKER)\n" \
	"* REGISTRY = $(REGISTRY)\n" \
	"* REPOSITORY = $(REPOSITORY)\n" \
	"* TAG = $(TAG)\n" \
	"* DOCKER_REL = $(DOCKER_REL)\n" \
	"* DOCKER_BUILD_ARGS = $(DOCKER_BUILD_ARGS)\n" \
	"* MANIFEST = $(MANIFEST)\n" \
	"* SIGNATURE = $(SIGNATURE)\n" \
	"* KEY_ID = $(KEY_ID)\n" \
	"* KEY_FILE_NAME = $(KEY_FILE_NAME)\n" \
	"* KEY_FILE_DIR = $(KEY_FILE_DIR)\n" \
	"* TRUST_KEY_FILE = $(TRUST_KEY_FILE)\n" \
	"* TEST_CMD = $(TEST_CMD)\n"

.PHONY: build
build:
	$(DOCKER) build $(DOCKER_BUILD_ARGS) -t $(LOCAL_IMAGE) $(PROJECT_PATH)

.PHONY: tag
tag:
	$(DOCKER) tag $(LOCAL_IMAGE) $(TARGET_IMAGE)

.PHONY: push
push:
	$(DOCKER) push $(TARGET_IMAGE)

.PHONY: pull
pull:
	if ! $(DOCKER) history --quiet $(TARGET_IMAGE) 2> /dev/null >&2; then \
		docker pull $(TARGET_IMAGE); \
	fi

$(MANIFEST):
	$(SKOPEO) inspect --raw docker://$(TARGET_IMAGE) > $(MANIFEST)

$(SIGNATURE): $(MANIFEST) secret-key
	$(SKOPEO) standalone-sign $(MANIFEST) $(TARGET_IMAGE) $(KEY_ID) -o $(SIGNATURE)

.PHONY: import-key
import-key: $(KEY_FILE)
	# This requires you to have $(KEY_ID) in your keyring or a key file around.
	$(GPG) --import $(KEY_FILE)

.PHONY: secret-key
secret-key:
	if ! $(GPG) --list-secret-keys $(KEY_ID); then \
		$(MAKE) import-key; \
	fi

.PHONY: public-key
public-key:
ifeq ($(TRUST_KEY_FILE),1)
	if ! $(GPG) --list-keys $(KEY_ID); then \
		if test -r $(KEY_FILE); then \
		    $(MAKE) import-key; \
		else \
		    $(MAKE) fetch-key; \
		fi; \
	fi
else
	if ! $(GPG) --list-keys $(KEY_ID); then \
		$(MAKE) fetch-key; \
	fi
endif

.PHONY: sign
sign: $(SIGNATURE)

.PHONY: verify
verify: $(MANIFEST) public-key
	@if test "x$$(stat -c%s $(MANIFEST))" = "x0"; then \
		echo "The manifest file $(MANIFEST) looks broken, please remove and retry" >&2 ; \
		false ; \
	fi
	@test -r $(SIGNATURE) || $(MAKE) info fetch-signature
	@if test "x$$(stat -c%s $(SIGNATURE))" = "x0"; then \
		echo "The signature file $(SIGNATURE) looks broken, please remove and retry" >&2 ; \
		false ; \
	fi
	# Trying all subkeys
	@OK=0; for k in $$($(GPG) --list-keys --with-fingerprint --with-fingerprint --with-colons $(KEY_ID) | grep "^fpr:" | cut -d: -f10); do \
	    echo -n "Checking key $${k}... "; \
	    if $(SKOPEO) standalone-verify $(MANIFEST) $(TARGET_IMAGE) $${k} $(SIGNATURE) 2>> /tmp/skopeo-err; then \
	        OK=1; \
	        break; \
	    else \
	        echo "Nope"; \
	    fi; \
	done; \
	if test "x$${OK}" = "x1"; then \
	    echo -e "\n$(BANNER_LINE)\n$(INFO_MARK) Signature verification OK\n$(BANNER_LINE)"; \
		rm /tmp/skopeo-err; \
	else \
	    echo -e "\n$(BANNER_LINE)\n$(WARN_MARK) Signature verification FAILED\n$(BANNER_LINE)"; \
		echo -e "\nError output:\n"; \
		cat /tmp/skopeo-err; \
		rm /tmp/skopeo-err; \
	    false; \
	fi

.PHONY: test
test: build
	$(DOCKER) run --rm -t $(LOCAL_IMAGE) $(TEST_CMD)

.PHONY: bash
bash: build
	$(DOCKER) run --rm -t -i -v $(PROJECT_PATH):$(DOCKER_PROJECT_PATH):z $(LOCAL_IMAGE) /bin/bash

.PHONY: verify-image
verify-image:
	if ! $(DOCKER) history --quiet $(VERIFY_IMAGE) 2> /dev/null >&2; then \
	    $(DOCKER) build -t $(VERIFY_IMAGE) -f $(VERIFY_DOCKERFILE) $(PROJECT_PATH); \
	fi

.PHONY: sign-docker
sign-docker: verify-image
	$(DOCKER_VERIFY_MAKE) secret-key sign

.PHONY: verify-docker
verify-docker: verify-image
	$(DOCKER_VERIFY_MAKE) fetch-key verify

.PHONY: verify-image-shell
verify-image-shell: verify-image
	@echo For this target please define VERIFY_IMAGE_CMD.
	$(DOCKER_VERIFY_RUN) $(VERIFY_IMAGE_CMD)

.PHONY: clean-verify-image
clean-verify-image:
	$(DOCKER) rmi $(VERIFY_IMAGE)
