# SBCL build image for cl-uf2.
#
# Builds a modern SBCL from source on Debian bullseye (glibc 2.31). The
# official prebuilt SBCL binaries are linked against a newer glibc and would
# not run here; compiling from source makes the runtime link against the old
# glibc, so executables saved with it keep a low glibc floor and run on older
# Linux distributions.
FROM debian:bullseye

ENV SBCL_VERSION=2.6.7

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        sbcl \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Host SBCL (2.1.1 from apt) bootstraps the source build.
RUN curl -fsSL \
        "https://downloads.sourceforge.net/project/sbcl/sbcl/${SBCL_VERSION}/sbcl-${SBCL_VERSION}-source.tar.bz2" \
        -o /tmp/sbcl-source.tar.bz2 \
    && mkdir /tmp/sbcl-build \
    && tar -xjf /tmp/sbcl-source.tar.bz2 -C /tmp/sbcl-build --strip-components=1 \
    && cd /tmp/sbcl-build \
    && sh make.sh \
    && sh install.sh \
    && rm -rf /tmp/sbcl-build /tmp/sbcl-source.tar.bz2

# Quicklisp bootstrap; ~/.sbclrc loads it so build.lisp can ql:quickload.
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp \
    && sbcl --non-interactive --load /tmp/quicklisp.lisp \
           --eval '(quicklisp-quickstart:install)' \
    && rm /tmp/quicklisp.lisp \
    && echo '(load "~/quicklisp/setup.lisp")' >> /root/.sbclrc

# Preload cl-uf2 dependencies so CI builds do not download them again.
RUN sbcl --non-interactive \
         --eval '(ql:quickload (list "iterate" "metabang-bind" "clingon" "fiveam"))'
