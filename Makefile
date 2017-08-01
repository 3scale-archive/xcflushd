MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_PATH := $(patsubst %/,%,$(dir $(MKFILE_PATH)))

DOCKER_USER := user
DOCKER_APP_HOME := /home/$(DOCKER_USER)
DOCKER_PROJECT_PATH := $(DOCKER_APP_HOME)/app

# GnuPG 2 and skopeo are needed
GPG ?= $(shell which gpg2 2> /dev/null)
SKOPEO ?= $(shell which skopeo 2> /dev/null)
TAG ?= $(shell git describe --dirty)

REGISTRY ?= registry.hub.docker.com
REPOSITORY ?= 3scale

# Alex's key until a Red Hat 3scale API Management Platform Signing Key becomes
# official.
KEY_ID ?= 0x33E0ED94CC4D33000F56B35ACE229595A73A83B0

DOCKER_TAG = $(shell echo $(TAG) | sed -e 's/^v//')
DOCKER_REL ?= 1
DOCKER_VERSION = $(DOCKER_TAG)-$(DOCKER_REL)
DOCKER_BUILD_ARGS ?=
TARGET_IMAGE = $(REGISTRY)/$(REPOSITORY)/xcflushd:$(DOCKER_VERSION)

MANIFEST ?= xcflushd-image-$(DOCKER_VERSION).manifest
SIGNATURE ?= xcflushd-image-$(DOCKER_VERSION).signature

default: test

.PHONY: info
info:
	@echo -e "\n" \
	"The following variables _can_ be modified:\n\n" \
	"* GPG = $(GPG)\n" \
	"* SKOPEO = $(SKOPEO)\n" \
	"* REGISTRY = $(REGISTRY)\n" \
	"* REPOSITORY = $(REPOSITORY)\n" \
	"* TAG = $(TAG)\n" \
	"* DOCKER_REL = $(DOCKER_REL)\n" \
	"* DOCKER_BUILD_ARGS = $(DOCKER_BUILD_ARGS)\n" \
	"* MANIFEST = $(MANIFEST)\n" \
	"* SIGNATURE = $(SIGNATURE)\n" \
	"* KEY_ID = $(KEY_ID)\n"

.PHONY: build
build:
	docker build $(DOCKER_BUILD_ARGS) -t xcflushd:$(DOCKER_VERSION) $(PROJECT_PATH)

.PHONY: tag
tag:
	docker tag xcflushd:$(DOCKER_VERSION) $(TARGET_IMAGE)

.PHONY: push
push:
	docker push $(TARGET_IMAGE)

$(MANIFEST):
	$(SKOPEO) inspect --raw docker://$(TARGET_IMAGE) > $(MANIFEST)

$(SIGNATURE): $(MANIFEST)
	$(SKOPEO) standalone-sign $(MANIFEST) $(TARGET_IMAGE) $(KEY_ID) -o $(SIGNATURE)

.PHONY: sign
sign: $(SIGNATURE)

.PHONY: verify
verify: $(MANIFEST)
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

test: build
	docker run --rm -t xcflushd script/test

bash: build
	docker run --rm -t -i -v $(PROJECT_PATH):$(DOCKER_PROJECT_PATH):z xcflushd /bin/bash
