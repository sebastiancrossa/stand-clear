.PHONY: app test clean refresh-stops

APP_NAME := SubwayBar
BUILD_DIR := .build/release
APP_DIR := dist/$(APP_NAME).app

test:
	swift test

app:
	swift build -c release --product $(APP_NAME)
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp Support/Info.plist $(APP_DIR)/Contents/Info.plist
	cp -R $(BUILD_DIR)/SubwayBar_SubwayBarCore.bundle $(APP_DIR)/Contents/Resources/
	codesign --force --deep --sign - $(APP_DIR)
	@echo "Built $(APP_DIR)"

refresh-stops:
	mkdir -p .build/mta-static
	curl -sS -o .build/mta-static/gtfs_subway.zip https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip
	unzip -jo .build/mta-static/gtfs_subway.zip stops.txt -d Sources/SubwayBarCore/Resources

clean:
	swift package clean
	rm -rf dist

