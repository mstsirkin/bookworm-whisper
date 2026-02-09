.DEFAULT_GOAL := help

APP_HTML := app.html
VENDOR_DIR := vendor/mediabunny
BUNDLE := $(VENDOR_DIR)/dist/bundles/mediabunny.min.cjs
NODE_MODULES := $(VENDOR_DIR)/node_modules

.PHONY: help bundle update

help:
	@echo "Targets:"
	@echo "  help   Show this help (default)"
	@echo "  bundle Build Mediabunny bundle in vendor/mediabunny"
	@echo "  update Rebuild bundled Mediabunny and inline it into app.html"

bundle:
	@test -f "$(VENDOR_DIR)/package.json" || { echo "Missing $(VENDOR_DIR)/package.json" >&2; exit 1; }
	@if [ ! -d "$(NODE_MODULES)" ]; then \
		echo "Installing vendor dependencies..."; \
		cd "$(VENDOR_DIR)" && npm install; \
	fi
	@echo "Building Mediabunny bundle..."
	@cd "$(VENDOR_DIR)" && npx tsx scripts/bundle.ts
	@test -f "$(BUNDLE)" || { echo "Missing bundle: $(BUNDLE)" >&2; exit 1; }

update: bundle
	@echo "Inlining bundle into $(APP_HTML)..."
	@tmp="$$(mktemp)"; \
	awk -v bundle="$(BUNDLE)" '\
		BEGIN { injected = 0; in_bundle = 0 } \
		/<!-- MEDIABUNNY_BUNDLE_START -->/ && !injected { \
			print; \
			print "<!-- Bundled Mediabunny fork (inline) -->"; \
			print "<script>"; \
			while ((getline line < bundle) > 0) print line; \
			close(bundle); \
			print "</script>"; \
			in_bundle = 1; \
			injected = 1; \
			next; \
		} \
		in_bundle && /<!-- MEDIABUNNY_BUNDLE_END -->/ { \
			print; \
			in_bundle = 0; \
			next; \
		} \
		in_bundle { \
			next; \
		} \
		{ print } \
		END { \
			if (!injected) { \
				print "ERROR: could not find MEDIABUNNY_BUNDLE_START marker in app.html" > "/dev/stderr"; \
				exit 1; \
			} \
		} \
	' "$(APP_HTML)" > "$$tmp" && mv "$$tmp" "$(APP_HTML)"
	@echo "Updated $(APP_HTML) with $(BUNDLE)"
