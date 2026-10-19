DERIVED_DATA = build
APP_NAME = Stop Typing App
APP = $(DERIVED_DATA)/Build/Products/Debug/$(APP_NAME).app

.PHONY: all project build test run clean

all: build

project:
	xcodegen generate --quiet --use-cache

build: project
	xcodebuild -project StopTyping.xcodeproj -scheme StopTyping -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) -quiet build

test:
	swift test --package-path StopTypingCore

run: build
	-pkill -x "$(APP_NAME)"
	while pgrep -qx "$(APP_NAME)"; do sleep 0.2; done
	open "$(APP)"

clean:
	rm -rf $(DERIVED_DATA) StopTyping.xcodeproj
