PLUGIN_ID  ?= yuler.omaports
PLUGIN_DIR ?= $(HOME)/.config/omarchy/plugins/$(PLUGIN_ID)
REPO       := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SHELL      := /bin/bash

.PHONY: link unlink test validate enable disable restart

# Point Omarchy at this checkout. Refuse to delete an existing copied plugin;
# the plugins dir entry must be absent or a symlink. Validate forbids symlinks *inside*
# the folder, and plugin remove already knows how to unlink a checkout.
link:
	mkdir -p "$(dir $(PLUGIN_DIR))"
	@if [[ -e $(PLUGIN_DIR) && ! -L $(PLUGIN_DIR) ]]; then \
	  echo "refusing to replace non-symlink plugin directory: $(PLUGIN_DIR)" >&2; \
	  echo "remove it explicitly if you intend to replace it" >&2; \
	  exit 1; \
	fi
	ln -sfn "$(REPO)" "$(PLUGIN_DIR)"
	@echo "linked $(PLUGIN_DIR) -> $(REPO)"
	$(MAKE) validate

unlink:
	@if [[ -L $(PLUGIN_DIR) ]]; then \
	  rm "$(PLUGIN_DIR)"; \
	  echo "removed $(PLUGIN_DIR)"; \
	elif [[ -e $(PLUGIN_DIR) ]]; then \
	  echo "refusing to remove $(PLUGIN_DIR): not a symlink" >&2; \
	  exit 1; \
	else \
	  echo "nothing to unlink"; \
	fi

test:
	node test/model-test.js

validate: test
	omarchy plugin validate "$(REPO)"

enable: link
	omarchy plugin enable "$(PLUGIN_ID)" --section right

disable:
	omarchy plugin disable "$(PLUGIN_ID)"

restart:
	omarchy restart shell
