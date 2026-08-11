ARG GO_IMAGE=rancher/hardened-build-base:v1.26.5b2
ARG XX_IMAGE=rancher/mirrored-tonistiigi-xx:1.6.1

FROM --platform=$BUILDPLATFORM ${XX_IMAGE} AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS base
COPY --from=xx / /
RUN set -x && \
    apk --no-cache add \
    clang \
    file \
    git \
    lld \
    linux-headers \
    make

FROM --platform=$BUILDPLATFORM base AS builder
ARG TARGETARCH
ARG TARGETOS
ARG SRC=github.com/kubernetes/autoscaler
ARG PKG=github.com/kubernetes/autoscaler
RUN git clone https://${SRC}.git $GOPATH/src/${PKG}
ARG TAG=1.8.24
WORKDIR $GOPATH/src/${PKG}/addon-resizer
RUN git branch -a
RUN git checkout addon-resizer-${TAG} -b ${TAG}
RUN ls

COPY go-mod-overrides ./go-mod-overrides
RUN go-mod-overrides.sh ./go-mod-overrides

RUN GIT_COMMIT=$(git rev-parse --short HEAD) && \
    if [ "${TARGETARCH}" = "amd64" ]; then \
        GOARCH=${TARGETARCH} \
        GO_LDFLAGS="-linkmode=external \
        -X ${PKG}/pkg/version.GitCommit=${GIT_COMMIT} \
        -X ${PKG}/pkg/version.Version=${TAG} \
        " go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o pod_nanny ./nanny/main/; \
    else \
        CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
        go build \
        -ldflags "-extldflags \"-static\" -X ${PKG}/pkg/version.GitCommit=${GIT_COMMIT} -X ${PKG}/pkg/version.Version=${TAG}" \
        -gcflags=-trimpath=${GOPATH}/src \
        -o pod_nanny ./nanny/main/; \
    fi

RUN go-assert-static.sh pod_nanny
RUN if [ "${TARGETARCH}" = "amd64" ]; then \
        go-assert-boring.sh pod_nanny; \
    fi
RUN cp pod_nanny /pod_nanny

FROM ${GO_IMAGE} AS strip_binary
COPY --from=builder /pod_nanny /pod_nanny
RUN strip /pod_nanny

FROM scratch
COPY --from=strip_binary /pod_nanny /pod_nanny
ENTRYPOINT ["/pod_nanny"]
