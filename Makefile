CC = clang
CFLAGS = -Wall -g -fobjc-arc -framework Foundation -framework Cocoa -framework Carbon -framework UserNotifications
SRC_DIR = src
BUILD_DIR = build
APP_NAME = StopTyping
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
EXECUTABLE = keylogger
TARGET = $(MACOS_DIR)/$(EXECUTABLE)

all: app

app: $(APP_DIR)

$(APP_DIR): $(TARGET) $(CONTENTS_DIR)/Info.plist $(RESOURCES_DIR)/StopTyping.icns
	codesign --entitlements StopTyping.entitlements --force --sign - $(APP_DIR)
	@echo "Application bundle created and signed at $(APP_DIR)"


SOURCES = $(SRC_DIR)/main.m $(SRC_DIR)/AppDelegate.m $(SRC_DIR)/KeyboardMonitor.m $(SRC_DIR)/Notifications.m $(SRC_DIR)/Accessibility.m $(SRC_DIR)/PermissionsManager.m

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
