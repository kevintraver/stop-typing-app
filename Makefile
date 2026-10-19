CC = clang
CFLAGS = -Wall -g -fobjc-arc -framework Foundation -framework Cocoa -framework Carbon -framework UserNotifications -framework WebKit
SRC_DIR = src
BUILD_DIR = build
APP_NAME = StopTyping
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
EXECUTABLE = keylogger
TARGET = $(MACOS_DIR)/$(EXECUTABLE)
ICONSET_DIR = StopTyping.iconset

all: app

app: $(APP_DIR)


$(APP_DIR): $(TARGET) $(CONTENTS_DIR)/Info.plist $(RESOURCES_DIR)/StopTyping.icns
	# Optionally include a custom notification image if present
	@if [ -f keyboard-off.png ]; then \
	  cp keyboard-off.png $(RESOURCES_DIR)/keyboard-off.png; \
	  echo "Copied keyboard-off.png into app bundle Resources"; \
	fi
	codesign --entitlements StopTyping.entitlements --force --sign - $(APP_DIR)
	@echo "Application bundle created and signed at $(APP_DIR)"


SOURCES = $(SRC_DIR)/main.m $(SRC_DIR)/AppDelegate.m $(SRC_DIR)/KeyboardMonitor.m $(SRC_DIR)/Notifications.m $(SRC_DIR)/Accessibility.m $(SRC_DIR)/PermissionsManager.m $(SRC_DIR)/SVGRenderer.m

$(TARGET): $(SOURCES) | $(MACOS_DIR)
	$(CC) $(CFLAGS) $^ -o $@
	codesign --entitlements StopTyping.entitlements --force --sign - $@
	touch $@  # Ensure it has a fresh timestamp

$(CONTENTS_DIR)/Info.plist: Info.plist | $(CONTENTS_DIR)
	cp Info.plist $@
	# Create a PkgInfo file (helps macOS identify the app properly)
	echo "APPL????" > $(CONTENTS_DIR)/PkgInfo

$(RESOURCES_DIR)/StopTyping.icns: StopTyping.icns | $(RESOURCES_DIR)
	cp StopTyping.icns $@

# --- Icon build pipeline ---
# Provide keyboard-off.svg at repo root; we generate StopTyping.icns from it.
ICON_SVG = keyboard-off.svg
SVG2PNG = $(BUILD_DIR)/svg2png

StopTyping.icns: $(ICON_SVG) $(SVG2PNG)
	@echo "Generating .iconset from $(ICON_SVG)"
	rm -rf $(ICONSET_DIR)
	mkdir -p $(ICONSET_DIR)
	# Render a crisp 1024x1024 master PNG via WebKit
	$(SVG2PNG) $(ICON_SVG) $(ICONSET_DIR)/icon_512x512@2x.png 1024 || (echo "svg2png failed" && exit 1)
	# Downscale to required sizes
	sips -Z 512 $(ICONSET_DIR)/icon_512x512@2x.png --out $(ICONSET_DIR)/icon_512x512.png >/dev/null
	sips -Z 256 $(ICONSET_DIR)/icon_512x512@2x.png --out $(ICONSET_DIR)/icon_256x256.png >/dev/null
	cp $(ICONSET_DIR)/icon_256x256.png $(ICONSET_DIR)/icon_128x128@2x.png
	sips -Z 128 $(ICONSET_DIR)/icon_256x256.png --out $(ICONSET_DIR)/icon_128x128.png >/dev/null
	sips -Z 64  $(ICONSET_DIR)/icon_128x128.png --out $(ICONSET_DIR)/icon_32x32@2x.png >/dev/null
	sips -Z 32  $(ICONSET_DIR)/icon_32x32@2x.png  --out $(ICONSET_DIR)/icon_32x32.png >/dev/null
	sips -Z 16  $(ICONSET_DIR)/icon_32x32.png    --out $(ICONSET_DIR)/icon_16x16.png >/dev/null
	cp $(ICONSET_DIR)/icon_32x32.png $(ICONSET_DIR)/icon_16x16@2x.png
	cp $(ICONSET_DIR)/icon_512x512@2x.png $(ICONSET_DIR)/icon_256x256@2x.png

	@echo "Building StopTyping.icns"
	iconutil -c icns $(ICONSET_DIR) -o StopTyping.icns
	@echo "Created StopTyping.icns"

$(SVG2PNG): tools/svg2png.m | $(BUILD_DIR)
	$(CC) -fobjc-arc -framework Foundation -framework WebKit -framework AppKit tools/svg2png.m -o $(SVG2PNG)

$(MACOS_DIR):
	mkdir -p $(MACOS_DIR)

$(CONTENTS_DIR):
	mkdir -p $(CONTENTS_DIR)

$(RESOURCES_DIR):
	mkdir -p $(RESOURCES_DIR)

clean:
	# Don't remove the whole build directory, just the executable
	# This helps maintain app identity for permissions
	rm -f $(BUILD_DIR)/$(EXECUTABLE)
	rm -f $(MACOS_DIR)/$(EXECUTABLE)
	
clean-all:
	# This completely removes the build directory
	# Will require re-granting permissions
	rm -rf $(BUILD_DIR)

# Build and run the standalone executable for development
dev: $(BUILD_DIR)/$(EXECUTABLE)

$(BUILD_DIR)/$(EXECUTABLE): $(SOURCES) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $^ -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

run-app: app
	open $(APP_DIR)

# Run without rebuilding the entire app
run-quick:
	# Just recompile the executable and replace it in the existing app bundle
	mkdir -p $(MACOS_DIR)
	$(CC) $(CFLAGS) $(SOURCES) -o $(MACOS_DIR)/$(EXECUTABLE)
	open $(APP_DIR)

run-dev: dev
	@echo "⚠️  WARNING: Running as standalone executable - notifications will not work!"
	@echo "   Use 'make run-app' to run from .app bundle with full functionality"
	$(BUILD_DIR)/$(EXECUTABLE)

# Test notification registration
test-notifications: app
	@echo "Testing notification registration..."
	@echo "1. The app should appear in System Settings → Notifications"
	@echo "2. Run this command: make run-app"
	@echo "3. Check if 'StopTyping' appears in the notifications list"
	@echo "4. If it doesn't appear, try restarting your Mac"
	@echo ""
	@echo "Opening notification settings..."
	open "x-apple.systempreferences:com.apple.preference.notifications"

# Install to Applications folder (may help with notification registration)
install: app
	@echo "Installing to Applications folder..."
	cp -r build/StopTyping.app /Applications/
	@echo "Installed to /Applications/StopTyping.app"
	@echo "Now run: open /Applications/StopTyping.app"

# Run from Applications folder
run-installed:
	open /Applications/StopTyping.app

# Check notification status
check-notifications:
	@echo "Checking notification status..."
	osascript -e 'tell application "System Settings" to activate'
	osascript -e 'delay 1'
	osascript -e 'tell application "System Events" to tell process "System Settings" to click menu item "Notifications" of menu "View" of menu bar 1'
	@echo "System Settings → Notifications should now be open"
	@echo "Look for 'StopTyping' in the list"

.PHONY: all clean clean-all app dev run-app run-quick run-dev
