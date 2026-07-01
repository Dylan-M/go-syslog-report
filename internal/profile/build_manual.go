//go:build !use_auto

package profile

import (
	syslog "github.com/leodido/go-syslog/v4"
	"github.com/leodido/go-syslog/v4/rfc3164"
	"github.com/leodido/go-syslog/v4/rfc5424"
)

const detectionMode = "manual detection (pre-auto)"

// manualMachine routes each message to the RFC3164 or RFC5424 parser using
// leading-byte signatures, for library versions that predate the auto package.
type manualMachine struct {
	p3164 Parser
	p5424 Parser
}

func buildMachine(o3164, o5424 []syslog.MachineOption) Parser {
	return &manualMachine{
		p3164: rfc3164.NewMachine(o3164...),
		p5424: rfc5424.NewMachine(o5424...),
	}
}

func (m *manualMachine) Parse(input []byte) (syslog.Message, error) {
	if isRFC3164(input) {
		return m.p3164.Parse(input)
	}
	return m.p5424.Parse(input)
}

// isRFC3164 reports whether the input, past any PRI, opens with an RFC3164
// month or a four-digit RFC3339 year. Everything else defaults to RFC5424,
// mirroring the routing the library's later auto package settled on.
func isRFC3164(b []byte) bool {
	if len(b) > 0 && b[0] == '<' {
		i := 0
		for i < len(b) && b[i] != '>' {
			i++
		}
		if i < len(b) {
			b = b[i+1:]
		}
	}
	return hasMonthPrefix(b) || hasYear4Prefix(b)
}

func hasMonthPrefix(b []byte) bool {
	if len(b) < 4 || b[3] != ' ' {
		return false
	}
	switch string(b[:3]) {
	case "Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec":
		return true
	}
	return false
}

func hasYear4Prefix(b []byte) bool {
	if len(b) < 5 || b[4] != '-' {
		return false
	}
	for i := 0; i < 4; i++ {
		if b[i] < '0' || b[i] > '9' {
			return false
		}
	}
	return true
}
