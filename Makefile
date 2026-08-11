SEVERITIES = HIGH,CRITICAL

UNAME_M = $(shell uname -m)
ARCH =
ifeq ($(UNAME_M), x86_64)
	ARCH = amd64
else ifeq ($(UNAME_M), aarch64)
	ARCH = arm64
else
	ARCH = $(UNAME_M)
endif

BUILD_META=-build$(shell date +%Y%m%d)
PKG ?= github.com/kubernetes/autoscaler
SRC ?= github.com/kubernetes/autoscaler
TAG ?= ${GITHUB_ACTION_TAG}
export DOCKER_BUILDKIT?=1

ifeq ($(TAG),)
TAG := 1.8.24$(BUILD_META)
endif

REPO ?= rancher
IMAGE_NAME = hardened-addon-resizer
REGISTRY_IMAGE = $(REPO)/$(IMAGE_NAME)
IMAGE = $(REGISTRY_IMAGE):$(TAG)

BUILDDIR ?= $(CURDIR)/build
METADATA_FILE ?= $(BUILDDIR)/$(subst /,-,$(REGISTRY_IMAGE))-$(ARCH).metadata.json
IID_FILE_FLAG ?=
IID_FILE_PATH := $(if $(IID_FILE_FLAG),$(word 2, $(IID_FILE_FLAG)))
MACHINE := rancher

BUILD_OPTS = \
	--platform=linux/$(ARCH) \
	--build-arg PKG=$(PKG) \
	--build-arg SRC=$(SRC) \
	--build-arg TAG=$(TAG:$(BUILD_META)=) \
	--tag "$(IMAGE)-$(ARCH)" \
	--tag "$(IMAGE)"

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

.PHONY: buildx-machine
buildx-machine:
	docker buildx inspect $(MACHINE) > /dev/null 2>&1 || \
		docker buildx create --name=$(MACHINE) --platform=linux/arm64,linux/amd64

.PHONY: image-build
image-build:
	docker buildx build \
		$(BUILD_OPTS) \
		--load \
		.

.PHONY: push-image
push-image: $(BUILDDIR)
	docker buildx build \
		$(BUILD_OPTS) \
		--metadata-file $(METADATA_FILE) \
		$(IID_FILE_FLAG) \
		$(BUILDX_ARGS) \
		--push \
		.

.PHONY: push-prime-image
push-prime-image:
	BUILDX_ARGS="--sbom=true --attest type=provenance,mode=max" \
	$(MAKE) push-image

.PHONY: manifest-push
manifest-push: $(BUILDDIR) | buildx-machine
	if [ -n "$(MULTI_ARCH)" ]; then \
		d=""; \
		for a in $(MULTI_ARCH); do \
			f=$(BUILDDIR)/$(subst /,-,$(REGISTRY_IMAGE))-$$a.metadata.json; \
			d="$$d $$(jq -r '.["containerimage.digest"]' $$f)"; \
		done; \
		docker buildx imagetools create \
			--builder=$(MACHINE) \
			-t $(IMAGE) \
			$$d; \
	else \
		docker buildx imagetools create \
			--builder=$(MACHINE) \
			-t $(IMAGE) \
			$$(jq -r '.["containerimage.digest"]' $(METADATA_FILE)); \
	fi
ifneq ($(strip $(IID_FILE_PATH)),)
	docker buildx imagetools inspect --format "{{json .Manifest}}" $(IMAGE) | jq -r '.digest' > "$(IID_FILE_PATH)"
endif

.PHONY: image-scan
image-scan:
	trivy --severity $(SEVERITIES) --no-progress --ignore-unfixed image $(IMAGE)

.PHONY: log
log:
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "REPO=$(REPO)"
	@echo "IMAGE=$(IMAGE)"
	@echo "PKG=$(PKG)"
	@echo "SRC=$(SRC)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
	@echo "ARCH=$(ARCH)"
	@echo "BUILDDIR=$(BUILDDIR)"
	@echo "REGISTRY_IMAGE=$(REGISTRY_IMAGE)"

