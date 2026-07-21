.PHONY: app test clean refresh-stops

APP_NAME := StandClear
BUILD_DIR := .build/release
APP_DIR := dist/$(APP_NAME).app
CORE_RESOURCE_BUNDLE := StandClear_StandClearCore.bundle

test:
	swift test

app:
	swift build -c release --product $(APP_NAME)
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp Support/Info.plist $(APP_DIR)/Contents/Info.plist
	cp -R $(BUILD_DIR)/$(CORE_RESOURCE_BUNDLE) $(APP_DIR)/Contents/Resources/
	codesign --force --deep --sign - $(APP_DIR)
	@echo "Built $(APP_DIR)"

refresh-stops:
	mkdir -p .build/mta-static
	curl -sS -o .build/mta-static/gtfs_subway.zip https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip
	unzip -jo .build/mta-static/gtfs_subway.zip stops.txt transfers.txt -d Sources/StandClearCore/Resources
	unzip -p .build/mta-static/gtfs_subway.zip trips.txt | awk -F, 'NR > 1 {print $$2 "," $$1}' > .build/mta-static/trip_routes.csv
	unzip -p .build/mta-static/gtfs_subway.zip stop_times.txt | awk -F, 'FNR == NR {route[$$1] = $$2; next} FNR > 1 && ($$1 in route) {print $$2 "," route[$$1]}' .build/mta-static/trip_routes.csv - > .build/mta-static/stop_routes.csv
	awk -F, 'FNR == NR {if (FNR > 1) parent[$$1] = ($$6 == "" ? $$1 : $$6); next} ($$1 in parent) {print parent[$$1] "," $$2}' Sources/StandClearCore/Resources/stops.txt .build/mta-static/stop_routes.csv | sort -u | awk 'BEGIN {print "station_id,route_id"} {print}' > .build/mta-static/station_routes.csv
	test "$$(wc -l < .build/mta-static/station_routes.csv)" -gt 1
	cp .build/mta-static/station_routes.csv Sources/StandClearCore/Resources/station_routes.csv

clean:
	swift package clean
	rm -rf dist
