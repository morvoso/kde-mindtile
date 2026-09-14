# MindTile: the MindOS window layouts as a KWin script.

ID := mindtile
PKG := package

.PHONY: test session session-multi keys install uninstall reload dist

## Unit tests for the layout engine (Node).
test:
	node --test tests/

## The script in a headless KWin with its own config dir; screenshots in build/session.
session:
	tests/kwin-session.sh tests/scenarios/basic.sh

session-multi:
	MT_OUTPUTS=2 tests/kwin-session.sh tests/scenarios/multi.sh

## Install or upgrade the script and the widget in the running session.
install:
	./install.sh

uninstall:
	./install.sh --uninstall

reload: install

## Take Plasma's default keys for MindTile (tools/claim-keys.sh --release undoes it).
keys:
	tools/claim-keys.sh

## A .kwinscript file for System Settings > KWin Scripts > Install from File.
dist:
	mkdir -p build && rm -f build/$(ID).kwinscript
	cd $(PKG) && bsdtar --format zip -cf ../build/$(ID).kwinscript *
