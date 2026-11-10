SPOON := iPhoneSnap.spoon
SPOONS_DIR := $(HOME)/.hammerspoon/Spoons

.PHONY: build install uninstall clean

# Regenerate docs.json and pack dist/iPhoneSnap.spoon.zip (needs the hs CLI).
build:
	./build.sh

# Symlink the working copy into Hammerspoon for development.
install:
	@if [ -d "$(SPOONS_DIR)/$(SPOON)" ] && [ ! -L "$(SPOONS_DIR)/$(SPOON)" ]; then \
		echo "$(SPOONS_DIR)/$(SPOON) is a directory; remove it first" >&2; exit 1; \
	fi
	mkdir -p "$(SPOONS_DIR)"
	ln -sfn "$(CURDIR)/$(SPOON)" "$(SPOONS_DIR)/$(SPOON)"

uninstall:
	rm -f "$(SPOONS_DIR)/$(SPOON)"

# Remove the release zip and the helper binary the Spoon compiles on first use.
clean:
	rm -rf dist $(SPOON)/iphone-snap $(SPOON)/iphone-snap.sha256
