# Current state

A snapshot of how completely `leodido/go-syslog` extracts the catalog across the
4.x line, and the reasons behind each number. Regenerate any row with the
`make` targets in the README. Figures below are as of 2026-07-01.

## Buckets

- **FULL**: parsed with no error, a timestamp, a message, and a *plausible*
  hostname all present.
- **PARTIAL**: a message came back but is incomplete, errored, or has a hostname
  that looks mis-parsed (see the FULL caveat below).
- **NONE**: nothing extractable.

## Snapshot

| target  | detection | FULL | PARTIAL | NONE |
|---------|-----------|-----:|--------:|-----:|
| v4.0.0  | manual    |   36 |      63 |   47 |
| v4.1.0  | manual    |   37 |      62 |   47 |
| v4.2.0  | manual    |   37 |      62 |   47 |
| v4.3.0  | manual    |   36 |      63 |   47 |
| v4.4.0  | manual    |   36 |      63 |   47 |
| v4.5.0  | auto      |   39 |      90 |   17 |
| develop | auto      |   39 |      90 |   17 |
| PR #66  | auto      |   44 |      93 |    9 |

Total examples: 146.

## How to read this chart

Three things must be kept in mind, or the numbers mislead.

### 1. The v4.5.0 detection boundary

The library's `auto` package (RFC3164-vs-RFC5424 routing) first appears in
v4.5.0. Versions before it are measured with this tool's own manual router, so
the pre-4.5 rows are **not directly comparable** to v4.5.0 and later. The
detection path differs, not just the library version. The large NONE drop from
47 (pre-4.5) to 17 (v4.5.0) is therefore a mix of two things: the real `auto`
package routing better, and more options being available. It is not a clean
capability delta. Comparisons *within* the auto regime (v4.5.0, develop, PR #66)
are clean.

### 2. FULL is a heuristic, not verified correctness

FULL requires a timestamp, a message, and a hostname that passes a plausibility
check (rejects a trailing colon, brackets, whitespace, a purely numeric value,
or emptiness). That check exists because the parser sometimes returns three
non-nil fields that are actually a mis-parse. It does **not** verify the values
are correct against ground truth, because the catalog does not yet carry
expected values. So FULL is an upper bound: "structurally full with a plausible
hostname." Adding per-example ground truth is the planned next step.

### 3. Why the plausibility check matters (a real false-positive story)

Before the check, v4.0.0 reported 46 FULL against v4.5.0's 41, which looked like
a regression. About 12 of v4.0.0's were mis-parses: the loose pre-4.5 parsing
grabbed a timestamp year or a process tag as the hostname. Examples:

- `<27>Aug 23 13:01:21 2019: %USER-3-ERR: Unspec[1824]: ...` gave `host="2019:"`
  (the year, from a year-bearing BSD timestamp).
- pfSense gave `host="filterlog[12345]:"` (the process tag; pfSense sends no
  hostname).

With the check, v4.0.0 drops to 36 and now sits just below v4.5.0's 39, which is
the expected direction. The apparent regression was false positives, not a real
loss.

## Why each version lands where it does

Option availability drives most of it. This tool enables a curated "known" set;
the generator emits only the options a given version actually has:

| option                | available from |
|-----------------------|----------------|
| WithBestEffort        | v4.0.0         |
| WithRFC3339           | v4.0.0         |
| WithYear              | v4.0.0         |
| WithSecondFractions   | v4.3.0         |
| WithMessageCounter    | v4.3.0         |
| WithSequenceNumber    | v4.3.0         |
| WithCiscoHostname     | v4.3.0         |
| WithLenientDay        | v4.4.0         |
| WithEmbeddedNewlines  | v4.5.0         |
| `auto` package        | v4.5.0         |
| WithOptionalPriority  | unreleased (PR stack #63/#64) |

- **v4.0.0 to v4.2.0** run with only best-effort, RFC3339, and year handling, so
  they sit lowest (36 to 37 FULL). The small wobble across these is within noise.
- **v4.3.0** gains fractional seconds and the Cisco prefix options; **v4.4.0**
  gains lenient-day. These help specific variants but do not move the headline
  FULL much under manual routing.
- **v4.5.0** adds embedded-newline handling and, more importantly, the `auto`
  package. NONE falls sharply (to 17) and FULL rises to 39.
- **PR #66** is the stacked work (#62 to #66). The tool auto-adds
  `WithOptionalPriority` (new since the release), which lets priorityless
  vendor messages parse. FULL rises to 44 and NONE falls to 9.

## Known limitations

- **No ground-truth validation yet.** FULL confirms structure and a plausible
  hostname, not correct values. Planned: expected hostname/message (or a regex)
  per catalog entry, checked alongside the heuristic.
- **The manual router is not the library's.** It mirrors the routing the `auto`
  package settled on, but for pre-4.5 versions it is this tool's code, so pre-4.5
  numbers reflect our routing plus the old parser, not a shipped `auto` package.
