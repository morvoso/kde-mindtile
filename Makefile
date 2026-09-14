# MindTile: Floating, Tiles and Columns layouts for KWin, and a panel widget.

ID := mindtile
PKG := package

.PHONY: test tools effect session session-multi keys install uninstall reload dist

## Unit tests for the layout engine (Node).
test:
	node --test tests/

## The Meta+wheel KWin effect, built against the installed KWin.
effect: build/effect/mindtile_wheel.so

build/effect/mindtile_wheel.so: effect/mindtile_wheel.cpp effect/metadata.json effect/build.sh
	effect/build.sh build/effect

## Test helper: sends clicks, keys and the wheel to a headless KWin.
build/tools/mtinput: tests/tools/mtinput.c tests/tools/fake-input.xml
	mkdir -p build/tools
	wayland-scanner client-header tests/tools/fake-input.xml build/tools/fake-input-client.h
	wayland-scanner private-code tests/tools/fake-input.xml build/tools/fake-input-protocol.c
	cc -O2 -Wall -Ibuild/tools -o $@ tests/tools/mtinput.c build/tools/fake-input-protocol.c $$(pkg-config --cflags --libs wayland-client)

tools: build/tools/mtinput effect

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

## Store uploads: build/mindtile-<version>.kwinscript for KWin Scripts and
## build/mindtile-widget-<version>.plasmoid for Plasma 6 applets.
VERSION := $(shell sed -n 's/.*"Version": "\(.*\)".*/\1/p' $(PKG)/metadata.json)
WIDGET_VERSION := $(shell sed -n 's/.*"Version": "\(.*\)".*/\1/p' widget/metadata.json)

dist:
	@test "$(VERSION)" = "$(WIDGET_VERSION)" || { echo "package and widget versions differ: $(VERSION) $(WIDGET_VERSION)"; exit 1; }
	mkdir -p build/dist && rm -f build/dist/*
	cd $(PKG) && bsdtar --format zip -cf ../build/dist/$(ID)-$(VERSION).kwinscript metadata.json contents
	cd widget && bsdtar --format zip -cf ../build/dist/$(ID)-widget-$(VERSION).plasmoid metadata.json contents
	@ls -l build/dist
