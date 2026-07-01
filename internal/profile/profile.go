// Package profile defines the parser configuration the conformance report
// measures against.
//
// Nothing here hard-codes which options or which construction strategy to use.
// The option set is generated from the target version (see cmd/gen and the
// Makefile's KNOWN_* lists), and the machine-construction strategy is chosen by
// a build tag the Makefile sets from a capability probe (build_auto.go vs
// build_manual.go). That keeps the compiled code free of any symbol the target
// version lacks, so it builds across the whole 4.x line.
package profile

import syslog "github.com/leodido/go-syslog/v4"

// Parser is the minimal surface the report needs. Both the auto package's
// machine and the manual-detection machine satisfy it.
type Parser interface {
	Parse(input []byte) (syslog.Message, error)
}

// NewMachine builds the parser from the generated option set using whichever
// construction strategy the build selected.
func NewMachine() Parser {
	return buildMachine(Options3164(), Options5424())
}

// Mode reports the construction strategy compiled in ("auto package" or
// "manual detection"), for the report header.
func Mode() string { return detectionMode }
