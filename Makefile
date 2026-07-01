LIB     ?= .lib/go-syslog
REPO    ?= https://github.com/leodido/go-syslog
CATALOG ?= catalog.jsonl

# The curated "known" options we want, as names. The generator emits only those
# actually present in the target version, so this compiles against any 4.x.
# Arg-taking options (e.g. WithYear) get their argument from cmd/gen's argExpr.
KNOWN_3164 := WithBestEffort WithRFC3339 WithSecondFractions WithYear \
              WithLenientDay WithEmbeddedNewlines WithMessageCounter \
              WithSequenceNumber WithCiscoHostname
KNOWN_5424 := WithBestEffort

GEN = go run ./cmd/gen -lib $(LIB) -known3164 "$(KNOWN_3164)" -known5424 "$(KNOWN_5424)"

# report runs the generator, then the report with build tags chosen from the
# target's capabilities. $(1) is a shell expression yielding the label.
# Uses the auto package when the target has it, else the manual detector.
define report
	$(GEN); \
	tags="generated"; test -d $(LIB)/auto && tags="$$tags use_auto"; \
	echo "build tags: $$tags"; \
	go run -tags "$$tags" ./cmd/report -catalog $(CATALOG) -label "$(1)" $(if $(DUMP),-dump,)
endef

# Clone the library on first use.
$(LIB):
	git clone --quiet $(REPO) $(LIB)

.PHONY: report-release report-develop report-pr

# A published release. `make report-release` uses the latest tag; `TAG=v4.2.0`
# pins one. Supports the whole 4.x line.
report-release: | $(LIB)
	@git -C $(LIB) fetch --quiet --tags origin; \
	 tag="$(TAG)"; test -n "$$tag" || tag=$$(git -C $(LIB) tag -l 'v*' | sort -V | tail -1); \
	 git -C $(LIB) checkout --quiet $$tag; \
	 $(call report,$$tag)

# Tip of develop.
report-develop: | $(LIB)
	@git -C $(LIB) fetch --quiet origin develop; \
	 git -C $(LIB) checkout --quiet -B develop origin/develop; \
	 $(call report,develop@$$(git -C $(LIB) rev-parse --short HEAD))

# A specific PR's head commit, e.g. `make report-pr PR=66`. The exact SHA is pinned.
report-pr: | $(LIB)
	@test -n "$(PR)" || { echo "usage: make report-pr PR=<number>"; exit 1; }
	@git -C $(LIB) fetch --quiet origin pull/$(PR)/head; \
	 sha=$$(git -C $(LIB) rev-parse FETCH_HEAD); \
	 echo "PR #$(PR) -> $$sha"; \
	 git -C $(LIB) checkout --quiet --detach $$sha; \
	 $(call report,PR#$(PR)@$$sha)
