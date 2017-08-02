MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_PATH := $(patsubst %/,%,$(dir $(MKFILE_PATH)))

DOCKER_USER := user
DOCKER_APP_HOME := /home/$(DOCKER_USER)
DOCKER_PROJECT_PATH := $(DOCKER_APP_HOME)/app

PROJECT_NAME ?= xcflushd

# GnuPG 2 and skopeo are needed
GPG ?= $(shell which gpg2 2> /dev/null)
SKOPEO ?= $(shell which skopeo 2> /dev/null)
DOCKER ?= $(shell which docker 2> /dev/null)
TAG ?= $(shell git describe --dirty)

REGISTRY ?= registry.hub.docker.com
REPOSITORY ?= 3scale

# Alex's key until a Red Hat 3scale API Management Platform Signing Key becomes
# official.
KEY_ID ?= 0x33E0ED94CC4D33000F56B35ACE229595A73A83B0
KEY_FILE_NAME ?= $(KEY_ID).asc
KEY_FILE_DIR ?= $(PROJECT_PATH)
KEY_FILE = $(KEY_FILE_DIR)/$(KEY_FILE_NAME)

DOCKER_TAG = $(shell echo $(TAG) | sed -e 's/^v//')
DOCKER_REL ?= 1
DOCKER_VERSION = $(DOCKER_TAG)-$(DOCKER_REL)
DOCKER_BUILD_ARGS ?=
LOCAL_IMAGE = $(PROJECT_NAME):$(DOCKER_VERSION)
TARGET_IMAGE = $(REGISTRY)/$(REPOSITORY)/$(LOCAL_IMAGE)

MANIFEST ?= $(PROJECT_NAME)-image-$(DOCKER_VERSION).manifest
SIGNATURE ?= $(PROJECT_NAME)-image-$(DOCKER_VERSION).signature

TEST_CMD ?= script/test

VERIFY_DOCKERFILE = Dockerfile.verify
VERIFY_IMAGE = $(PROJECT_NAME):verify

default: test

.PHONY: fetch-key
fetch-key:
	$(GPG) --recv-keys $(KEY_ID)

.PHONY: info
info:
	@echo -e "\n" \
	"The following variables _can_ be modified:\n\n" \
	"* PROJECT_NAME = $(PROJECT_NAME)\n" \
	"* GPG = $(GPG)\n" \
	"* SKOPEO = $(SKOPEO)\n" \
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
	if ! $(GPG) --list-keys $(KEY_ID); then \
		if test -r $(KEY_FILE); then \
		    $(MAKE) import-key; \
		else \
		    $(MAKE) fetch-key; \
		fi; \
	fi

.PHONY: sign
sign: $(SIGNATURE)

.PHONY: verify
verify: $(MANIFEST) public-key
	# Trying all subkeys
	@OK=0; for k in $$($(GPG) --list-keys --with-fingerprint --with-fingerprint --with-colons $(KEY_ID) | grep "^fpr:" | cut -d: -f10); do \
	    echo -n "Checking key $${k}... "; \
	    if $(SKOPEO) standalone-verify $(MANIFEST) $(TARGET_IMAGE) $${k} $(SIGNATURE) 2> /dev/null; then \
	        OK=1; \
			break; \
		else \
			echo "Nope"; \
		fi; \
	done; \
	test "x$${OK}" = "x1"

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
	$(DOCKER) run --rm --security-opt label:disable -v $(PROJECT_PATH):/home/user/app -ti $(VERIFY_IMAGE) make TARGET_IMAGE=$(TARGET_IMAGE) MANIFEST=$(MANIFEST) SIGNATURE=$(SIGNATURE) KEY_ID=$(KEY_ID) secret-key sign

.PHONY: verify-docker
verify-docker: verify-image
	$(DOCKER) run --rm --security-opt label:disable -v $(PROJECT_PATH):/home/user/app -ti $(VERIFY_IMAGE) make TARGET_IMAGE=$(TARGET_IMAGE) MANIFEST=$(MANIFEST) SIGNATURE=$(SIGNATURE) KEY_ID=$(KEY_ID) fetch-key verify

.PHONY: verify-image-shell
verify-image-shell: verify-image
	@echo For this target please define VERIFY_IMAGE_CMD.
	$(DOCKER) run --rm --security-opt label:disable -v $(PROJECT_PATH):/home/user/app -ti $(VERIFY_IMAGE)

.PHONY: clean-verify-image
clean-verify-image:
	$(DOCKER) rmi $(VERIFY_IMAGE)
