// Package gosyslogreport embeds the default variant catalog so the report
// binary is self-contained. Override the catalog at runtime with -catalog.
package gosyslogreport

import _ "embed"

//go:embed catalog.jsonl
var Catalog []byte
