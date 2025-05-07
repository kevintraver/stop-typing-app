CC = clang
CFLAGS = -Wall -g -framework Foundation -framework Cocoa -framework Carbon
SRC_DIR = src
BUILD_DIR = build
APP_NAME = KeyboardMonitor
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
EXECUTABLE = keylogger
TARGET = $(MACOS_DIR)/$(EXECUTABLE)

all: app

app: $(APP_DIR)

$(APP_DIR): $(TARGET) $(CONTENTS_DIR)/Info.plist
	@echo "Application bundle created at $(APP_DIR)"

$(TARGET): $(SRC_DIR)/main.m | $(MACOS_DIR)
	$(CC) $(CFLAGS) $< -o $@
	touch $@  # Ensure it has a fresh timestamp

$(CONTENTS_DIR)/Info.plist: Info.plist | $(CONTENTS_DIR)
	cp $< $@
	# Create a PkgInfo file (helps macOS identify the app properly)
	echo "APPL????" > $(CONTENTS_DIR)/PkgInfo

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

$(BUILD_DIR)/$(EXECUTABLE): $(SRC_DIR)/main.m | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

run-app: app
	open $(APP_DIR)

# Run without rebuilding the entire app
run-quick:
	# Just recompile the executable and replace it in the existing app bundle
	mkdir -p $(MACOS_DIR)
	$(CC) $(CFLAGS) $(SRC_DIR)/main.m -o $(MACOS_DIR)/$(EXECUTABLE)
	open $(APP_DIR)

run-dev: dev
	$(BUILD_DIR)/$(EXECUTABLE)

.PHONY: all clean clean-all app dev run-app run-quick run-dev