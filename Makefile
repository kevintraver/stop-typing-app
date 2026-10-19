DERIVED_DATA = build
APP_NAME = Stop Typing App
APP = $(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app
# The app runs from here rather than from build/, so `make clean` can't delete it from under you.
# Input Monitoring follows the signing identity and bundle ID, not the path, so the grant carries over.
INSTALL_DIR = $(HOME)/Applications
INSTALLED_APP = $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: all project build test install run clean

all: build

project:
	xcodegen generate --quiet --use-cache

build: project
	xcodebuild -project StopTyping.xcodeproj -scheme StopTyping -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) -quiet build

test:
	swift test --package-path StopTypingCore

# Replaces the bundle rather than copying over it, so files removed from the app don't linger.
install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALLED_APP)"
	ditto "$(APP)" "$(INSTALLED_APP)"

run: install
	-pkill -x "$(APP_NAME)"
	while pgrep -qx "$(APP_NAME)"; do sleep 0.2; done
	open "$(INSTALLED_APP)"

clean:
	rm -rf $(DERIVED_DATA) StopTyping.xcodeproj
