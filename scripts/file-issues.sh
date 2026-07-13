#!/usr/bin/env bash
# File one idempotent GitHub issue per unclassified option from a classify.sh
# JSONL stream. Usage: file-issues.sh <verdicts.jsonl> <release-tag>
# Env: GITHUB_REPOSITORY (owner/repo), GH_TOKEN. Set DRY_RUN=1 to print instead
# of creating issues.
set -euo pipefail

verdicts="${1:?usage: file-issues.sh <verdicts.jsonl> <release-tag>}"
rel="${2:?usage: file-issues.sh <verdicts.jsonl> <release-tag>}"
repo="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY}"

if [ ! -s "$verdicts" ]; then
  echo "no unclassified options"
  exit 0
fi

create() { # $1=title $2=body
  if [ "${DRY_RUN:-}" = "1" ]; then
    echo "--- would create issue ---"
    echo "title: $1"
    echo "$2"
    echo "---"
  else
    gh issue create --repo "$repo" --title "$1" --body "$2"
  fi
}

exists() { # $1=title ; true if an issue with this exact title exists (any state)
  gh issue list --repo "$repo" --state all --search "\"$1\" in:title" \
    --json title --jq '.[].title' 2>/dev/null | grep -Fxq "$1"
}

while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  pkg=$(jq -r .pkg <<<"$line")
  name=$(jq -r .name <<<"$line")
  noarg=$(jq -r .noarg <<<"$line")
  verdict=$(jq -r .verdict <<<"$line")
  title="gen: unclassified go-syslog option ${pkg}.${name}"

  if [ "${DRY_RUN:-}" != "1" ] && exists "$title"; then
    echo "issue already exists for ${pkg}.${name}; skipping"
    continue
  fi

  if [ "$noarg" = "true" ]; then
    body=$(cat <<EOF
\`${pkg}.${name}\` is a new no-arg option present in go-syslog \`${rel}\`, in neither KNOWN nor DENY.

A/B measurement on the catalog (option excluded → included):
- FULL: $(jq -r .full_ex <<<"$line") → $(jq -r .full_in <<<"$line")
- core-fields: $(jq -r .core_ex <<<"$line") → $(jq -r .core_in <<<"$line")
- NONE: $(jq -r .none_ex <<<"$line") → $(jq -r .none_in <<<"$line")

Verdict: appears to **${verdict}** extraction.

Currently auto-enabled (denylist default). Acknowledge by adding it to \`KNOWN\` (keep enabled) or \`DENY\` (exclude) in the Makefile.
EOF
)
  else
    body=$(cat <<EOF
\`${pkg}.${name}\` is a new arg-taking option in go-syslog \`${rel}\`, in neither KNOWN nor DENY. It cannot be auto-enabled because it needs a value, so it is currently unused.

To enable it, add an entry to \`cmd/gen\`'s \`argExpr\` map. To acknowledge without enabling, add it to \`DENY\` in the Makefile.
EOF
)
  fi

  create "$title" "$body"
  echo "filed issue for ${pkg}.${name}"
done < "$verdicts"
