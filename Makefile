LIB     ?= .lib/go-syslog
REPO    ?= https://github.com/leodido/go-syslog
# This tool's own version, baked into the binary. Overridden by CI to the tag.
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo dev)

# Two hand-maintained "acknowledged" lists. A no-arg option present in the
# target is ENABLED unless it is in DENY, so coverage never silently drops when
# go-syslog adds a useful option. KNOWN records the options we've reviewed and
# kept; DENY records extraction-reducing options we exclude. An option in
# neither is "unclassified": still enabled (if no-arg), and surfaced by the
# nightly for triage. Arg-taking options (e.g. WithYear) enable via cmd/gen's
# argExpr map.
KNOWN_3164 := WithBestEffort WithRFC3339 WithSecondFractions WithYear \
              WithLenientDay WithEmbeddedNewlines WithMessageCounter \
              WithSequenceNumber WithCiscoHostname WithOptionalPriority
KNOWN_5424 := WithBestEffort WithOptionalPriority
DENY_3164  :=
DENY_5424  := WithCompliantMsg

GEN = go run ./cmd/gen -lib $(LIB) \
        -known3164 "$(KNOWN_3164)" -known5424 "$(KNOWN_5424)" \
        -deny3164 "$(DENY_3164)" -deny5424 "$(DENY_5424)"

# build compiles a static, self-contained report binary for the currently
# checked-out library. It does not run it. $(1) is the go-syslog version id
# baked into the header; $(2) is the output binary name under bin/.
define build
	$(GEN); \
	tags="generated"; test -d $(LIB)/auto && tags="$$tags use_auto"; \
	echo "build tags: $$tags" >&2; \
	mkdir -p bin; \
	CGO_ENABLED=0 go build -tags "$$tags" \
	  -ldflags "-X main.version=$(VERSION) -X main.gsVersion=$(1)" \
	  -o "bin/$(2)" ./cmd/report; \
	echo "built bin/$(2)"
endef

# Clone the library on first use.
$(LIB):
	git clone --quiet $(REPO) $(LIB)

.PHONY: report-release report-develop report-pr

# Compile a binary against a published release. `make report-release` uses the
# latest tag; `TAG=v4.2.0` pins one. Supports the whole 4.x line.
report-release: | $(LIB)
	@git -C $(LIB) fetch --quiet --tags origin; \
	 tag="$(TAG)"; test -n "$$tag" || tag=$$(git -C $(LIB) tag -l 'v*' | sort -V | tail -1); \
	 git -C $(LIB) checkout --quiet $$tag; \
	 $(call build,$$tag,report-release-for-gs-$$tag)

# Compile a binary against the tip of develop.
report-develop: | $(LIB)
	@git -C $(LIB) fetch --quiet origin develop; \
	 git -C $(LIB) checkout --quiet -B develop origin/develop; \
	 sha=$$(git -C $(LIB) rev-parse --short=12 HEAD); \
	 $(call build,develop@$$sha,report-develop-for-gs-$$sha)

# Compile a binary against a specific PR's head commit, e.g. `make report-pr PR=66`.
report-pr: | $(LIB)
	@test -n "$(PR)" || { echo "usage: make report-pr PR=<number>"; exit 1; }
	@git -C $(LIB) fetch --quiet origin pull/$(PR)/head; \
	 sha=$$(git -C $(LIB) rev-parse --short=12 FETCH_HEAD); \
	 echo "PR #$(PR) -> $$sha"; \
	 git -C $(LIB) checkout --quiet --detach $$sha; \
	 $(call build,PR#$(PR)@$$sha,report-pr-$(PR)-for-gs-$$sha)
