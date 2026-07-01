//go:build !generated

package profile

import syslog "github.com/leodido/go-syslog/v4"

// Stub option set for builds without generation (keeps the package compilable
// for `go vet` and editors). The Makefile always generates before building, so
// real reports never use these.

func Options3164() []syslog.MachineOption { return nil }
func Options5424() []syslog.MachineOption { return nil }

// AutoAdded names the options the generator discovered beyond the known list.
func AutoAdded() []string { return nil }
