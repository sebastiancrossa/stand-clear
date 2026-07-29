.PHONY: app release test clean refresh-static-data refresh-stops

APP_NAME := StandClear
BUILD_DIR := .build/release
APP_DIR := dist/$(APP_NAME).app
CORE_RESOURCE_BUNDLE := StandClear_StandClearCore.bundle
SPARKLE_ARTIFACT := .build/artifacts/sparkle/Sparkle
SPARKLE_FRAMEWORK_SRC := $(SPARKLE_ARTIFACT)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
SPARKLE_FRAMEWORK_DST := $(APP_DIR)/Contents/Frameworks/Sparkle.framework
CODESIGN_IDENTITY ?= -
# Core Location is unreachable under the hardened runtime without this entitlement.
ENTITLEMENTS := Support/StandClear.entitlements
CODESIGN_FLAGS := --force --entitlements $(ENTITLEMENTS)
CODESIGN_NESTED_FLAGS := --force
ifneq ($(CODESIGN_IDENTITY),-)
CODESIGN_FLAGS += --options runtime --timestamp
CODESIGN_NESTED_FLAGS += --options runtime --timestamp
endif

test:
	swift test

app:
	swift build -c release --product $(APP_NAME)
	@test -d "$(SPARKLE_FRAMEWORK_SRC)" || (echo "error: Sparkle.framework missing at $(SPARKLE_FRAMEWORK_SRC); run swift package resolve" >&2; exit 1)
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources $(APP_DIR)/Contents/Frameworks
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp Support/Info.plist $(APP_DIR)/Contents/Info.plist
	cp Support/AppIcon.icns $(APP_DIR)/Contents/Resources/AppIcon.icns
	cp -R $(BUILD_DIR)/$(CORE_RESOURCE_BUNDLE) $(APP_DIR)/Contents/Resources/
	cp -R "$(SPARKLE_FRAMEWORK_SRC)" "$(SPARKLE_FRAMEWORK_DST)"
	# XPC services are only required for sandboxed apps; removing them avoids
	# the nested-signing order that most often corrupts non-sandboxed bundles.
	rm -f "$(SPARKLE_FRAMEWORK_DST)/XPCServices"
	rm -rf "$(SPARKLE_FRAMEWORK_DST)/Versions/B/XPCServices"
	# Match the arm64-only app binary and keep the shipped framework small.
	/usr/bin/lipo -thin arm64 \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Sparkle" \
		-output "$(SPARKLE_FRAMEWORK_DST)/Versions/B/Sparkle.arm64"
	mv "$(SPARKLE_FRAMEWORK_DST)/Versions/B/Sparkle.arm64" \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Sparkle"
	/usr/bin/lipo -thin arm64 \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Autoupdate" \
		-output "$(SPARKLE_FRAMEWORK_DST)/Versions/B/Autoupdate.arm64"
	mv "$(SPARKLE_FRAMEWORK_DST)/Versions/B/Autoupdate.arm64" \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Autoupdate"
	/usr/bin/lipo -thin arm64 \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Updater.app/Contents/MacOS/Updater" \
		-output "$(SPARKLE_FRAMEWORK_DST)/Versions/B/Updater.app/Contents/MacOS/Updater.arm64"
	mv "$(SPARKLE_FRAMEWORK_DST)/Versions/B/Updater.app/Contents/MacOS/Updater.arm64" \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Updater.app/Contents/MacOS/Updater"
	# Sign inner-to-outer. Do not apply the app's location entitlements to Sparkle.
	codesign $(CODESIGN_NESTED_FLAGS) --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Autoupdate"
	codesign $(CODESIGN_NESTED_FLAGS) --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK_DST)/Versions/B/Updater.app"
	codesign $(CODESIGN_NESTED_FLAGS) --sign "$(CODESIGN_IDENTITY)" \
		"$(SPARKLE_FRAMEWORK_DST)"
	codesign $(CODESIGN_FLAGS) --sign "$(CODESIGN_IDENTITY)" $(APP_DIR)
	@echo "Built $(APP_DIR)"

release:
	./Scripts/package-release.sh "$(RELEASE_VERSION)" "$(PRERELEASE)" "$(BUILD_NUMBER)"

refresh-static-data:
	mkdir -p .build/mta-static/input
	curl -fsSL --connect-timeout 15 --max-time 180 -o .build/mta-static/gtfs_subway.zip https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip
	unzip -jo .build/mta-static/gtfs_subway.zip routes.txt trips.txt stop_times.txt stops.txt transfers.txt shapes.txt feed_info.txt -d .build/mta-static/input
	cp .build/mta-static/input/stops.txt .build/mta-static/input/transfers.txt Sources/StandClearCore/Resources/
	awk -F, 'NR > 1 {print $$2 "," $$1}' .build/mta-static/input/trips.txt > .build/mta-static/trip_routes.csv
	awk -F, 'FNR == NR {route[$$1] = $$2; next} FNR > 1 && ($$1 in route) {print $$2 "," route[$$1]}' .build/mta-static/trip_routes.csv .build/mta-static/input/stop_times.txt > .build/mta-static/stop_routes.csv
	awk -F, 'FNR == NR {if (FNR > 1) parent[$$1] = ($$6 == "" ? $$1 : $$6); next} ($$1 in parent) {print parent[$$1] "," $$2}' Sources/StandClearCore/Resources/stops.txt .build/mta-static/stop_routes.csv | sort -u | awk 'BEGIN {print "station_id,route_id"} {print}' > .build/mta-static/station_routes.csv
	test "$$(wc -l < .build/mta-static/station_routes.csv)" -gt 1
	cp .build/mta-static/station_routes.csv Sources/StandClearCore/Resources/station_routes.csv
	swift run -c release StandClearStaticDataBuilder .build/mta-static/input Sources/StandClearCore/Resources/subway_geometry.scgm

refresh-stops: refresh-static-data

clean:
	swift package clean
	rm -rf dist
