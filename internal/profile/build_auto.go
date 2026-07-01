//go:build use_auto

package profile

import (
	syslog "github.com/leodido/go-syslog/v4"
	"github.com/leodido/go-syslog/v4/auto"
)

const detectionMode = "auto package"

// buildMachine uses the library's own auto package (present from v4.5.0), so
// the report exercises the real detection-and-parse path a consumer would use.
func buildMachine(o3164, o5424 []syslog.MachineOption) Parser {
	return auto.NewMachine(
		auto.WithRFC3164Options(o3164...),
		auto.WithRFC5424Options(o5424...),
	)
}
