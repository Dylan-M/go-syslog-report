module github.com/Dylan-M/go-syslog-report

go 1.22

require github.com/leodido/go-syslog/v4 v4.5.0

// The library under test is a local clone, so the build can point at any
// branch, tag, or PR head. The Makefile manages what the clone is checked
// out to. See README.
replace github.com/leodido/go-syslog/v4 => ./.lib/go-syslog
