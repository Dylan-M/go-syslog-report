#!/usr/bin/env bash
# Classify the unclassified options of the go-syslog version currently checked
# out in $LIB, by A/B measurement: build+run the report with each option
# excluded vs included and compare.
#
# Verdict axis (lexicographic, FULL primary): including the option
#   - lowers FULL                      -> reduces
#   - raises FULL                      -> helps
#   - FULL equal, lowers core-fields   -> reduces
#   - FULL equal, raises core-fields   -> helps
#   - FULL+core equal, raises NONE     -> reduces
#   - FULL+core equal, lowers NONE     -> helps
#   - all equal                        -> neutral
# Arg-taking options can't be A/B tested (no value), so verdict is "arg".
#
# Emits one JSON object per unclassified option to stdout.
# Inputs via env: LIB, KNOWN_3164, KNOWN_5424, DENY_3164, DENY_5424.
set -euo pipefail

LIB="${LIB:-.lib/go-syslog}"
tags="generated"; test -d "$LIB/auto" && tags="$tags use_auto"

gen() { # extra deny: $1=rfc3164 $2=rfc5424 ; $3 optional -unclassified path
  go run ./cmd/gen -lib "$LIB" \
    -known3164 "${KNOWN_3164:-}" -known5424 "${KNOWN_5424:-}" \
    -deny3164 "${DENY_3164:-} ${1:-}" -deny5424 "${DENY_5424:-} ${2:-}" \
    ${3:+-unclassified "$3"} >/dev/null 2>&1
}

metrics() { # build+run current generated profile, echo "FULL CORE NONE"
  go build -tags "$tags" -o /tmp/gsr-rpt ./cmd/report >/dev/null 2>&1
  /tmp/gsr-rpt | awk '/^TOTALS/{for(i=1;i<=NF;i++){
    if($i~/^FULL=/)f=substr($i,6); if($i~/^NONE=/)n=substr($i,6);
    if($i~/^core-fields=/)c=substr($i,13)} print f,c,n}'
}

unc=$(mktemp)
gen "" "" "$unc"   # base profile + unclassified list

while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  pkg=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pkg"])')
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  noarg=$(printf '%s' "$line" | python3 -c 'import json,sys;print(str(json.load(sys.stdin)["noarg"]).lower())')

  if [ "$noarg" != "true" ]; then
    printf '{"pkg":"%s","name":"%s","noarg":false,"verdict":"arg"}\n' "$pkg" "$name"
    continue
  fi

  if [ "$pkg" = "rfc3164" ]; then gen "$name" ""; else gen "" "$name"; fi
  read -r fex cex nex < <(metrics)       # excluded
  gen "" ""
  read -r fin cin nin < <(metrics)       # included

  if   [ "$fin" -lt "$fex" ]; then verdict=reduces
  elif [ "$fin" -gt "$fex" ]; then verdict=helps
  elif [ "$cin" -lt "$cex" ]; then verdict=reduces
  elif [ "$cin" -gt "$cex" ]; then verdict=helps
  elif [ "$nin" -gt "$nex" ]; then verdict=reduces
  elif [ "$nin" -lt "$nex" ]; then verdict=helps
  else verdict=neutral
  fi

  printf '{"pkg":"%s","name":"%s","noarg":true,"verdict":"%s","full_in":%s,"full_ex":%s,"core_in":%s,"core_ex":%s,"none_in":%s,"none_ex":%s}\n' \
    "$pkg" "$name" "$verdict" "$fin" "$fex" "$cin" "$cex" "$nin" "$nex"
done < "$unc"
rm -f "$unc" /tmp/gsr-rpt
