.DEFAULT_GOAL := help

APP_HTMLS := pdf.html epub.html
VENDOR_DIR := vendor/mediabunny
BUNDLE := $(VENDOR_DIR)/dist/bundles/mediabunny.min.cjs
NODE_MODULES := $(VENDOR_DIR)/node_modules

.PHONY: help init-submodules ensure-submodule bundle update

help:
	@echo "Targets:"
	@echo "  help             Show this help (default)"
	@echo "  init-submodules  Initialize git submodules"
	@echo "  bundle           Build Mediabunny bundle in vendor/mediabunny"
	@echo "  update           Rebuild bundled Mediabunny and inline it into pdf.html and epub.html"

init-submodules:
	@echo "Initializing git submodules..."
	@git submodule update --init --recursive

ensure-submodule:
	@test -f .gitmodules || { echo "Missing .gitmodules; vendor/mediabunny is expected to be a submodule." >&2; exit 1; }
	@status="$$(git submodule status -- "$(VENDOR_DIR)" 2>/dev/null || true)"; \
	if [ -z "$$status" ]; then \
		echo "Missing submodule registration for $(VENDOR_DIR)." >&2; \
		echo "Run: make init-submodules" >&2; \
		exit 1; \
	fi; \
	case "$${status%% *}" in \
		-*) \
			echo "Submodule $(VENDOR_DIR) is not initialized." >&2; \
			echo "Run: make init-submodules" >&2; \
			exit 1; \
			;; \
	esac

bundle: ensure-submodule
	@test -f "$(VENDOR_DIR)/package.json" || { echo "Missing $(VENDOR_DIR)/package.json. Run: make init-submodules" >&2; exit 1; }
	@if [ ! -d "$(NODE_MODULES)" ]; then \
		echo "Installing vendor dependencies..."; \
		cd "$(VENDOR_DIR)" && npm install; \
	fi
	@echo "Building Mediabunny bundle..."
	@cd "$(VENDOR_DIR)" && npx tsx scripts/bundle.ts
	@test -f "$(BUNDLE)" || { echo "Missing bundle: $(BUNDLE)" >&2; exit 1; }

update: bundle
	@set -e; \
	for app_html in $(APP_HTMLS); do \
		echo "Inlining bundle into $$app_html..."; \
		tmp="$$(mktemp)"; \
		awk -v bundle="$(BUNDLE)" -v app_html="$$app_html" '\
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
					print "ERROR: could not find MEDIABUNNY_BUNDLE_START marker in " app_html > "/dev/stderr"; \
					exit 1; \
				} \
			} \
		' "$$app_html" > "$$tmp" && mv "$$tmp" "$$app_html"; \
		echo "Updated $$app_html with $(BUNDLE)"; \
	done
