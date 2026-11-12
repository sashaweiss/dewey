# Notary profile for `make release`:
# {
#   "notaryProfile": "..."
# }
IDENTITY := release-identity.json

.PHONY: release

# Set VERBOSE (e.g., `make release VERBOSE=1`) to show each step's output.
VERBOSE :=

# Extra dewey-release flags go in ARGS, e.g. `make release ARGS=--dry-run`.
release:
	@test -f $(IDENTITY) || { echo "missing $(IDENTITY)" >&2; exit 1; }
	@profile=$$(jq -er .notaryProfile $(IDENTITY)) && \
	swift run $(if $(VERBOSE),,--quiet) --package-path DeweyRelease \
		dewey-release $(if $(VERBOSE),--verbose) \
		--notary-profile "$$profile" \
		$(ARGS)
