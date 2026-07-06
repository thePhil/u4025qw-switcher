#!/usr/bin/env pwsh
# Reproducible build of u4025qw.exe (Windows amd64), PowerShell 7 edition.
# Mirrors build.sh — same flags, same output. A binary built here is
# byte-for-byte identical to one built by build.sh on any OS, as long as the
# Go toolchain version matches, so IT can rebuild and confirm the SHA-256
# before adding the WDAC hash-allow rule (Option B in README.md).
#
# Reproducibility levers:
#   CGO_ENABLED=0        no host C toolchain in the mix (pure syscall anyway)
#   -trimpath            strip absolute source/module paths from the binary
#   -buildvcs=false      don't stamp git commit/dirty/time (this is a git repo)
#   -ldflags -buildid=   clear the build id so output depends only on inputs
#   -ldflags "-s -w"     drop symbol table + DWARF (also neutralises toolchain
#                        debug-format differences, e.g. GOEXPERIMENT=nodwarf5)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# Pin this and record it alongside the published hash.
$ExpectGo = 'go1.26.4'
$HaveGo = (go env GOVERSION)
if (-not $HaveGo.StartsWith($ExpectGo)) {
    Write-Warning "building with $HaveGo, published hash was made with $ExpectGo"
}

$exe = 'u4025qw.exe'
$env:CGO_ENABLED = '0'
$env:GOOS        = 'windows'
$env:GOARCH      = 'amd64'
$env:GOFLAGS     = ''

go build -trimpath -buildvcs=false '-ldflags=-s -w -buildid=' -o $exe .
if ($LASTEXITCODE -ne 0) { throw "go build failed ($LASTEXITCODE)" }

# Print the hash the WDAC rule will pin (uppercase hex; case-insensitive).
Get-FileHash -Algorithm SHA256 $exe | Format-List Algorithm, Hash, Path
