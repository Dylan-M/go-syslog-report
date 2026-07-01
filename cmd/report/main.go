// Command report runs every syslog variant in a catalog through the
// leodido/go-syslog parser and classifies how completely each one is
// extracted: FULL, PARTIAL, or NONE.
//
// The library version under test is selected by the build (see the Makefile
// and the replace directive in go.mod), so this program always reports on
// whatever go-syslog the module currently resolves to.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"time"

	syslog "github.com/leodido/go-syslog/v4"
	"github.com/leodido/go-syslog/v4/rfc3164"
	"github.com/leodido/go-syslog/v4/rfc5424"

	gosyslogreport "github.com/Dylan-M/go-syslog-report"
	"github.com/Dylan-M/go-syslog-report/internal/profile"
)

// Set at build time via -ldflags -X. version is this tool's own version;
// gsVersion is the go-syslog version the binary was compiled against.
var (
	version   = "dev"
	gsVersion = "(unspecified)"
)

type entry struct {
	Vendor           string   `json:"vendor"`
	Product          string   `json:"product"`
	VariantName      string   `json:"variant_name"`
	CanonicalExample []string `json:"canonical_examples"`
}

type bucket int

const (
	none bucket = iota
	partial
	full
)

func (b bucket) String() string {
	switch b {
	case full:
		return "FULL"
	case partial:
		return "PARTIAL"
	default:
		return "NONE"
	}
}

type result struct {
	entry   entry
	example string
	bucket  bucket
	missing []string
	err     string
	// extracted values, for -dump validation
	ts   string
	host string
	app  string
	msg  string
}

func base(msg syslog.Message) *syslog.Base {
	switch m := msg.(type) {
	case *rfc3164.SyslogMessage:
		return &m.Base
	case *rfc5424.SyslogMessage:
		return &m.Base
	}
	return nil
}

func classify(m profile.Parser, ex string) result {
	msg, err := m.Parse([]byte(ex))
	r := result{example: ex}
	if err != nil {
		r.err = err.Error()
	}
	if msg == nil {
		r.bucket = none
		return r
	}
	b := base(msg)
	ts := b != nil && b.Timestamp != nil
	host := b != nil && b.Hostname != nil
	message := b != nil && b.Message != nil
	if b != nil {
		if b.Timestamp != nil {
			r.ts = b.Timestamp.Format(time.RFC3339Nano)
		}
		if b.Hostname != nil {
			r.host = *b.Hostname
		}
		if b.Appname != nil {
			r.app = *b.Appname
		}
		if b.Message != nil {
			r.msg = *b.Message
		}
	}
	hostOK := host && plausibleHost(r.host)
	if !ts {
		r.missing = append(r.missing, "timestamp")
	}
	if !host {
		r.missing = append(r.missing, "hostname")
	} else if !hostOK {
		r.missing = append(r.missing, "hostname(suspect)")
	}
	if !message {
		r.missing = append(r.missing, "message")
	}
	if err == nil && ts && hostOK && message {
		r.bucket = full
	} else {
		r.bucket = partial
	}
	return r
}

// plausibleHost rejects extracted hostnames that are almost certainly a
// mis-parse (a timestamp fragment or a tag grabbed as the hostname) rather than
// a real hostname or IP. Heuristic only; true correctness needs per-example
// ground truth, which the catalog does not yet carry. Internal colons are
// allowed so IPv6 addresses survive; a trailing colon, brackets, whitespace, a
// purely numeric value, or emptiness are treated as mis-parses.
func plausibleHost(s string) bool {
	if s == "" || strings.ContainsAny(s, "[] ") || strings.HasSuffix(s, ":") {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return true // has a non-digit, so not a bare number
		}
	}
	return false // all digits: not a hostname
}

func main() {
	catalog := flag.String("catalog", "", "path to a variant catalog (JSONL); overrides the embedded catalog")
	dump := flag.Bool("dump", false, "print the extracted fields for every FULL result, for validation")
	flag.Parse()

	var src io.Reader = bytes.NewReader(gosyslogreport.Catalog)
	if *catalog != "" {
		f, err := os.Open(*catalog)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		defer f.Close()
		src = f
	}

	m := profile.NewMachine()

	var results []result
	sc := bufio.NewScanner(src)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		var e entry
		if err := json.Unmarshal(sc.Bytes(), &e); err != nil {
			fmt.Fprintln(os.Stderr, "bad catalog line:", err)
			os.Exit(1)
		}
		for _, ex := range e.CanonicalExample {
			r := classify(m, strings.TrimSpace(ex))
			r.entry = e
			results = append(results, r)
		}
	}

	report(results)
	if *dump {
		dumpFull(results)
	}
}

func dumpFull(rs []result) {
	fmt.Println("\nFULL extractions (validate that these are truly complete and correct):")
	for _, r := range rs {
		if r.bucket != full {
			continue
		}
		name := r.entry.Vendor
		if r.entry.Product != "" {
			name += "/" + r.entry.Product
		}
		fmt.Printf("  %s\n    in:   %s\n    ts=%q host=%q app=%q msg=%q\n", name, trunc(r.example), r.ts, r.host, r.app, r.msg)
	}
}

func report(rs []result) {
	var counts [3]int
	var pri, priless [3]int
	for _, r := range rs {
		counts[r.bucket]++
		if strings.HasPrefix(r.example, "<") {
			pri[r.bucket]++
		} else {
			priless[r.bucket]++
		}
	}

	fmt.Printf("go-syslog-report %s\n", version)
	fmt.Printf("library:   %s\n", gsVersion)
	fmt.Printf("generated: %s\n", time.Now().UTC().Format(time.RFC3339))
	fmt.Printf("detection: %s\n", profile.Mode())
	auto := profile.AutoAdded()
	if len(auto) == 0 {
		fmt.Printf("auto-added options: (none; release/base profile)\n\n")
	} else {
		fmt.Printf("auto-added options: %s\n\n", strings.Join(auto, ", "))
	}

	total := len(rs)
	fmt.Printf("TOTALS  examples=%d  FULL=%d  PARTIAL=%d  NONE=%d\n", total, counts[full], counts[partial], counts[none])
	fmt.Printf("  pri-bearing:  FULL=%d PARTIAL=%d NONE=%d\n", pri[full], pri[partial], pri[none])
	fmt.Printf("  priorityless: FULL=%d PARTIAL=%d NONE=%d\n\n", priless[full], priless[partial], priless[none])

	fmt.Println("PARTIAL (message returned but incomplete), the worklist to drive toward FULL:")
	printGroup(rs, partial)
	fmt.Println("\nNONE (nothing extractable):")
	printGroup(rs, none)
}

func printGroup(rs []result, b bucket) {
	var group []result
	for _, r := range rs {
		if r.bucket == b {
			group = append(group, r)
		}
	}
	sort.SliceStable(group, func(i, j int) bool {
		return group[i].entry.Vendor < group[j].entry.Vendor
	})
	if len(group) == 0 {
		fmt.Println("  (none)")
		return
	}
	for _, r := range group {
		name := r.entry.Vendor
		if r.entry.Product != "" {
			name += "/" + r.entry.Product
		}
		miss := ""
		if len(r.missing) > 0 {
			miss = "  missing=[" + strings.Join(r.missing, ",") + "]"
		}
		e := ""
		if r.err != "" {
			e = "  err=" + quote(r.err)
		}
		fmt.Printf("  %-28s%s%s\n      %s\n", name, miss, e, trunc(r.example))
	}
}

func quote(s string) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) > 80 {
		s = s[:80] + "..."
	}
	return "\"" + s + "\""
}

func trunc(s string) string {
	s = strings.ReplaceAll(s, "\n", "\\n")
	if len(s) > 88 {
		return s[:88] + "..."
	}
	return s
}
