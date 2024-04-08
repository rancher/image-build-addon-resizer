#ARG BCI_IMAGE=registry.suse.com/bci/bci-busybox
ARG GO_IMAGE=rancher/hardened-build-base:v1.20.14b1

#FROM ${BCI_IMAGE} as bci
FROM ${GO_IMAGE} as base

RUN set -x && \
    apk --no-cache add \
    git \
    make

FROM base as builder
ARG ARCH
ARG SRC=github.com/kubernetes/autoscaler
ARG PKG=github.com/kubernetes/autoscaler
RUN git clone https://${SRC}.git $GOPATH/src/${PKG}
ARG TAG=1.8.20
WORKDIR $GOPATH/src/${PKG}/addon-resizer
RUN git branch -a
RUN git checkout addon-resizer-${TAG} -b ${TAG}
RUN ls
RUN GOARCH=${ARCH} GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.VERSION=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o pod_nanny nanny/main/pod_nanny.go
RUN go-assert-static.sh pod_nanny
RUN if [ "${ARCH}" = "amd64" ]; then \
        go-assert-boring.sh pod_nanny; \
    fi
RUN install -s pod_nanny /usr/local/bin

FROM scratch
COPY --from=builder /usr/local/bin/pod_nanny /pod_nanny
ENTRYPOINT ["/pod_nanny"]
