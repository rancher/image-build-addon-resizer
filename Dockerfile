ARG GO_IMAGE=rancher/hardened-build-base:v1.22.10b1

FROM ${GO_IMAGE} AS base

RUN set -x && \
    apk --no-cache add \
    git \
    make

FROM base AS builder
ARG TARGETARCH
ARG SRC=github.com/kubernetes/autoscaler
ARG PKG=github.com/kubernetes/autoscaler
RUN git clone https://${SRC}.git $GOPATH/src/${PKG}
ARG TAG=1.8.23
WORKDIR $GOPATH/src/${PKG}/addon-resizer
RUN git branch -a
RUN git checkout addon-resizer-${TAG} -b ${TAG}
RUN ls

RUN GIT_COMMIT=$(git rev-parse --short HEAD) \
    GOARCH=${TARGETARCH} \
    GO_LDFLAGS="-linkmode=external \
    -X ${PKG}/pkg/version.GitCommit=${GIT_COMMIT} \
    -X ${PKG}/pkg/version.Version=${TAG} \
    " go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o pod_nanny ./nanny/main/

RUN go-assert-static.sh pod_nanny
RUN if [ "${TARGETARCH}" = "amd64" ]; then \
        go-assert-boring.sh pod_nanny; \
    fi
RUN install -s pod_nanny /usr/local/bin

FROM scratch
COPY --from=builder /usr/local/bin/pod_nanny /pod_nanny
ENTRYPOINT ["/pod_nanny"]
