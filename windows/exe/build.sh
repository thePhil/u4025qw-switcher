#!/usr/bin/env bash
# Reproducible build of u4025qw.exe (Windows amd64) from any platform with Go.
#
# The output is byte-for-byte identical across machines and directories given
# the same Go toolchain version, so IT can independently rebuild and confirm
# the SHA-256 before adding the WDAC hash-allow rule (Option B in README.md).
#
# Reproducibility levers:
#   CGO_ENABLED=0     no host C toolchain in the mix (pure syscall anyway)
#   -trimpath         strip absolute source/module paths from the binary
#   -buildvcs=false   don't stamp git commit/dirty/time (this is a git repo)
#   -ldflags -buildid=  clear the build id so output depends only on inputs
#   -ldflags "-s -w"  drop symbol table + DWARF (also neutralises toolchain
#                     debug-format differences, e.g. GOEXPERIMENT=nodwarf5)
set -euo pipefail
cd "$(dirname "$0")"

# Pin this and record it alongside the published hash.
EXPECT_GO="go1.26.4"
have_go="$(go env GOVERSION)"
[[ "$have_go" == "$EXPECT_GO"* ]] || \
  echo "warning: building with $have_go, published hash was made with $EXPECT_GO" >&2

CGO_ENABLED=0 GOOS=windows GOARCH=amd64 GOFLAGS= \
  go build -trimpath -buildvcs=false \
    -ldflags="-s -w -buildid=" \
    -o u4025qw.exe .

sha256sum u4025qw.exe
