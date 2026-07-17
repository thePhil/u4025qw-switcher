#!/usr/bin/env bash
# Reproducible build of u4025qw.exe (Windows amd64) from any platform with Go.
#
# The output is byte-for-byte identical across build hosts (Linux/macOS/Windows)
# and directories, so IT can independently rebuild and confirm the SHA-256
# before adding the WDAC hash-allow rule (Option B in README.md).
#
# Reproducibility levers:
#   GOTOOLCHAIN       pin the EXACT upstream Go release. Go embeds its version
#                     string into every binary and -trimpath cannot strip it,
#                     so the hash depends on the precise toolchain build — a
#                     custom GOEXPERIMENT build (e.g. go1.26.4-X:nodwarf5) does
#                     NOT produce the same bytes as stock go1.26.4. Pinning here
#                     makes the hash canonical regardless of the installed Go.
#                     Go auto-downloads this toolchain if it isn't present.
#   CGO_ENABLED=0     no host C toolchain in the mix (pure syscall anyway)
#   -trimpath         strip absolute source/module paths from the binary
#   -buildvcs=false   don't stamp git commit/dirty/time (this is a git repo)
#   -ldflags -buildid=  clear the build id so output depends only on inputs
#   -ldflags "-s -w"  drop symbol table + DWARF debug info
set -euo pipefail
cd "$(dirname "$0")"

# Override only if you mirror the toolchain yourself; the published hash is
# tied to this exact release.
export GOTOOLCHAIN="${GOTOOLCHAIN:-go1.26.4}"

CGO_ENABLED=0 GOOS=windows GOARCH=amd64 GOFLAGS= \
  go build -trimpath -buildvcs=false \
    -ldflags="-s -w -buildid=" \
    -o u4025qw.exe .

sha256sum u4025qw.exe
