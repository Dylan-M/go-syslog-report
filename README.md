# go-syslog-report

A conformance harness for [`leodido/go-syslog`](https://github.com/leodido/go-syslog).
It runs a catalog of real vendor syslog variants through the parser and reports,
for each example, how completely the library extracts it:

- **FULL**: parsed with no error, and a timestamp, message, and *plausible* hostname all present.
- **PARTIAL**: a message came back but is incomplete, errored, or has a hostname that looks mis-parsed. These are the interesting ones: they are close to full and show exactly what the parser is dropping.
- **NONE**: nothing extractable.

The goal is to shrink PARTIAL and NONE toward FULL over time.

For the current measured numbers across the 4.x line, and the reasons behind
them, see [CURRENT_STATE.md](CURRENT_STATE.md).

## Building report binaries

Each `make` target **compiles** a self-contained report binary; it does not run
it. The tool imports `go-syslog` through a `replace` directive pointing at a
local clone in `.lib/go-syslog`, and the Makefile moves that clone to the
version you want to measure, so one build can target a release, a branch, or an
open PR without editing `go.mod`.

```sh
make report-release            # latest release  -> bin/report-release-for-gs-<TAG>
make report-release TAG=v4.2.0 # a specific release tag
make report-develop            # develop tip     -> bin/report-develop-for-gs-<SHA>
make report-pr PR=66           # a PR head commit -> bin/report-pr-<N>-for-gs-<SHA>
```

Binaries land in `bin/`, named for the go-syslog version they were built
against, with that version and this tool's own version baked in via ldflags (both
shown in the report header). The catalog is embedded, so a binary is
self-contained: run it to get the report, or point it at a different catalog.

```sh
./bin/report-release-for-gs-v4.5.0                           # embedded catalog
./bin/report-release-for-gs-v4.5.0 -catalog other.jsonl      # override the catalog
```

`make report-pr PR=<n>` fetches `pull/<n>/head` and pins the exact commit SHA.
The clone is created on first use in `.lib/` and is git-ignored, as is `bin/`.
The whole 4.x line is supported (v4.0.0 is the floor); see the sections below.

## Releases

Pushing a `v*` tag compiles `report-release-for-gs-<TAG>` and attaches it to the
GitHub release. A nightly workflow, when go-syslog's develop has moved, compiles
`report-develop-for-gs-<SHA>`, runs it against the current catalog, and publishes
both the binary and a `nightly-report-for-<SHA>.txt` on a timestamped
pre-release.

## The catalog

`catalog.jsonl` is one JSON object per line. Each entry carries a vendor,
product, variant name, the RFC baseline it approximates, and one or more
`canonical_examples`. The harness scores every example.

## The extraction profile

Nothing about the profile is hard-coded in Go. The Makefile owns the curated
list of options to enable, as names, in `KNOWN_3164` / `KNOWN_5424`. Before each
run, `cmd/gen` reconciles that list against the target version's source and
writes `internal/profile/options_gen.go` calling only the options that version
actually has. So the compiled code never names a symbol the target lacks, and it
builds against any 4.x release.

`cmd/gen` also **auto-adds** any no-argument `With…() MachineOption` that is
present in the target but absent from the latest release, i.e. a genuinely new
option (this is how a PR's new option gets measured with no edits here). Options
already in the release stay owned by the `KNOWN_*` list. Arg-taking options get
their argument from a small map in `cmd/gen`; a new arg-taking option is printed
so it can be added there. Every run's header lists what was auto-added.

Semantic restrictors such as `WithCompliantMsg` are simply left out of the
`KNOWN_*` lists (and, being in the release, are never auto-added), since they
reduce extraction.

## Detection: `auto` package vs manual

The library's `auto` package (RFC3164-vs-RFC5424 routing) only exists from
v4.5.0. Two build files provide the machine, and the Makefile picks one from a
capability probe:

- `build_auto.go` (`//go:build use_auto`) uses the real `auto` package. Selected
  when the target has `auto/`, so v4.5.0+ and PRs measure the library's own
  routing.
- `build_manual.go` (`//go:build !use_auto`) routes with the same leading-byte
  signatures for versions that predate `auto`.

The file that imports `auto` is excluded when the target lacks the package, so
pre-v4.5.0 targets compile. Because pre-v4.5.0 uses manual routing, those numbers
are not directly comparable to v4.5.0+ (different detection path, not just a
different library version). The header prints which path was used.

The generated options file is git-ignored and build-tagged, so a stale copy can
never leak into another run.

## Validating FULL

FULL requires a plausible hostname, not just a non-nil one, because the parser
sometimes returns three non-nil fields that are actually a mis-parse (a
timestamp year or a process tag grabbed as the hostname). The plausibility check
rejects a trailing colon, brackets, whitespace, a purely numeric value, or
emptiness. It is a heuristic, not verified correctness; the values are not yet
checked against ground truth. Run a binary with `-dump` (for example
`./bin/report-release-for-gs-v4.5.0 -dump`) to print the extracted fields for
every FULL result and eyeball them. Adding per-example ground truth is the
planned next step (see CURRENT_STATE.md).
