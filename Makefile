PROJECT  := Zman-claude.xcodeproj
SCHEME   := Zman-claude
APP_NAME := Zman-claude
BUILD_DIR := build

VERSION := $(shell grep 'MARKETING_VERSION' $(PROJECT)/project.pbxproj | head -1 | sed 's/.*= *//;s/ *;.*//')
ZIP_NAME := $(APP_NAME)-$(VERSION).zip

.PHONY: build run release clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		SYMROOT=$(CURDIR)/$(BUILD_DIR) build

run: build
	-pkill -x "$(APP_NAME)" 2>/dev/null; sleep 0.5
	open "$(BUILD_DIR)/Release/$(APP_NAME).app"

release: build
	cd "$(BUILD_DIR)/Release" && zip -r "$(CURDIR)/$(ZIP_NAME)" "$(APP_NAME).app"
	@echo ""
	@echo "Built $(ZIP_NAME)"
	@echo "SHA256: $$(shasum -a 256 $(ZIP_NAME) | cut -d' ' -f1)"

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME)-*.zip
