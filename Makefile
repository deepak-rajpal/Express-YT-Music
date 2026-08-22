# Express YT Music - builds a .app bundle with swiftc only.
# Command Line Tools are enough; full Xcode is not required.
#
#   make            build build/Express YT Music.app (arm64)
#   make universal  build a fat arm64 + x86_64 binary
#   make run        build and launch
#   make install    copy into /Applications
#   make dmg        package a distributable disk image
#   make clean

APP_NAME  := Express YT Music
BINARY    := ExpressYTMusic
DEPLOY    := 13.0

BUILD     := build
APP       := $(BUILD)/$(APP_NAME).app

SOURCES   := $(wildcard Sources/*.swift)
SDK       := $(shell xcrun --show-sdk-path --sdk macosx)
ICNS      := $(BUILD)/AppIcon.icns

SWIFT_FLAGS := -O -sdk "$(SDK)" \
               -framework AppKit -framework WebKit -framework MediaPlayer \
               -framework ServiceManagement -framework Carbon

# App bundle paths are only ever used inside recipes, always quoted, because the
# bundle name contains spaces and make cannot express that in a target name.
.PHONY: all app universal icon sign run install dmg clean check test probe

all: app

app: icon
	@echo "==> building $(APP_NAME) (arm64)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@swiftc -target arm64-apple-macos$(DEPLOY) $(SWIFT_FLAGS) \
		-o "$(APP)/Contents/MacOS/$(BINARY)" $(SOURCES)
	@$(MAKE) --no-print-directory bundle
	@echo "==> built $(APP)"

universal: icon
	@echo "==> building $(APP_NAME) (universal)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" $(BUILD)/obj
	@swiftc -target arm64-apple-macos$(DEPLOY)  $(SWIFT_FLAGS) -o $(BUILD)/obj/$(BINARY)-arm64  $(SOURCES)
	@swiftc -target x86_64-apple-macos$(DEPLOY) $(SWIFT_FLAGS) -o $(BUILD)/obj/$(BINARY)-x86_64 $(SOURCES)
	@lipo -create -output "$(APP)/Contents/MacOS/$(BINARY)" \
		$(BUILD)/obj/$(BINARY)-arm64 $(BUILD)/obj/$(BINARY)-x86_64
	@$(MAKE) --no-print-directory bundle
	@lipo -info "$(APP)/Contents/MacOS/$(BINARY)"

# Resources + signature. Not meant to be called directly.
.PHONY: bundle
bundle:
	@cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp Resources/inject.js "$(APP)/Contents/Resources/inject.js"
	@if [ -f "$(ICNS)" ]; then cp "$(ICNS)" "$(APP)/Contents/Resources/AppIcon.icns"; fi
	@printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	@$(MAKE) --no-print-directory sign

icon: $(ICNS)

$(ICNS): Tools/makeicon.swift
	@echo "==> generating app icon"
	@mkdir -p $(BUILD)
	@swiftc -O -sdk "$(SDK)" -target arm64-apple-macos$(DEPLOY) -framework AppKit \
		-o $(BUILD)/makeicon Tools/makeicon.swift
	@$(BUILD)/makeicon $(BUILD)/AppIcon.iconset >/dev/null
	@iconutil -c icns $(BUILD)/AppIcon.iconset -o $(ICNS)
	@rm -rf $(BUILD)/AppIcon.iconset $(BUILD)/makeicon

# Ad-hoc signature: gives the bundle a stable identity so macOS remembers the
# permissions you granted it across rebuilds.
# To ship it, swap in your Developer ID:
#   codesign --deep --force --options runtime \
#     --sign "Developer ID Application: NAME (TEAMID)" "build/Express YT Music.app"
sign:
	@codesign --force --deep --sign - "$(APP)" 2>/dev/null || \
		echo "    (ad-hoc signing skipped)"

# Runs Resources/inject.js against Tests/fixture.html in a real WKWebView and
# asserts on the state it reports. Offline.
test:
	@mkdir -p $(BUILD)
	@echo "== first-party host matcher =="
	@swiftc -O -sdk "$(SDK)" -target arm64-apple-macos$(DEPLOY) \
		-o $(BUILD)/hosttest Sources/FirstPartyHosts.swift Tools/hosttest.swift
	@$(BUILD)/hosttest
	@echo ""
	@echo "== mini player layout =="
	@swiftc -O -sdk "$(SDK)" -target arm64-apple-macos$(DEPLOY) \
		-framework AppKit -o $(BUILD)/layouttest \
		Sources/MiniPlayerLayout.swift Tools/layouttest.swift
	@$(BUILD)/layouttest
	@echo ""
	@echo "== page bridge =="
	@swiftc -O -sdk "$(SDK)" -target arm64-apple-macos$(DEPLOY) \
		-framework AppKit -framework WebKit -o $(BUILD)/bridgetest Tools/bridgetest.swift
	@$(BUILD)/bridgetest

# Diagnostic: confirms Google still serves a real sign-in form to this web view.
# Hits accounts.google.com. No credentials are sent.
probe:
	@mkdir -p $(BUILD)
	@swiftc -O -sdk "$(SDK)" -target arm64-apple-macos$(DEPLOY) \
		-framework AppKit -framework WebKit -o $(BUILD)/probe Tools/probe.swift
	@$(BUILD)/probe

# Type-check without producing a binary.
check:
	@swiftc -typecheck -target arm64-apple-macos$(DEPLOY) $(SWIFT_FLAGS) $(SOURCES) \
		&& echo "==> type check passed"

run: app
	@pkill -x $(BINARY) 2>/dev/null || true
	@open "$(APP)"

install: app
	@echo "==> installing to /Applications"
	@pkill -x $(BINARY) 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R "$(APP)" "/Applications/$(APP_NAME).app"
	@echo "==> done. open \"/Applications/$(APP_NAME).app\""

dmg: universal
	@echo "==> packaging disk image"
	@rm -rf $(BUILD)/dmg && mkdir -p $(BUILD)/dmg
	@cp -R "$(APP)" "$(BUILD)/dmg/$(APP_NAME).app"
	@ln -s /Applications $(BUILD)/dmg/Applications
	@hdiutil create -quiet -volname "$(APP_NAME)" -srcfolder $(BUILD)/dmg \
		-ov -format UDZO "$(BUILD)/$(BINARY).dmg"
	@rm -rf $(BUILD)/dmg
	@echo "==> $(BUILD)/$(BINARY).dmg"

clean:
	@rm -rf $(BUILD)
