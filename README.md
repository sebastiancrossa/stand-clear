# Stand Clear

A small native macOS menu bar app that finds the closest NYC subway station and shows live ETAs for the lines you care about.

The interface is inspired by [Closing Doors](https://www.closingdoors.nyc/us-ny-subway). Station metadata and live arrival data come directly from the [MTA developer feeds](https://www.mta.info/developers).

## Requirements

- macOS 14 or newer
- Xcode 16 or newer

## Development

```sh
swift test
swift run StandClear
```

Running through SwiftPM is useful for development, but location permission requires the bundled app build:

```sh
make app
open dist/StandClear.app
```

On first launch, the app opens directly to the direction-and-line picker with every option unselected. After choosing at least one direction and line, those filters are saved for later launches. The picker includes the complete subway route catalog, rather than only the lines at the nearest station.

The app refreshes live arrival data every 30 seconds. By default, the menu bar shows the train icon; click it to open the full board or edit the saved filters.

Use the pin beside an arrival to keep that route and direction in the menu bar as a live minutes-and-seconds countdown, such as `Q ↑ 4:24`. One pin is supported at a time and is remembered across launches. It follows the nearest station, advances to the next matching train at zero, and shows `--:--` when no upcoming arrival is available. Pinning another service replaces the current pin; use the active row pin or the footer’s unpin button to remove it. Removing the pinned route or direction from the filters also clears the pin.

Click any arrival’s ETA to switch every row from floored whole minutes, such as `4 min`, to a minutes-and-seconds countdown, such as `4:24`. Click any ETA again to return every row to whole minutes.

To update the bundled station coordinates from the latest regular MTA static feed:

```sh
make refresh-stops
```

## Privacy

Stand Clear uses Core Location to choose a nearby station. Coordinates stay on the Mac and are never sent to the MTA or any other service.

## Data and trademarks

The repository includes the MTA static GTFS `stops.txt` file and consumes MTA GTFS-Realtime feeds under the MTA's published data terms. The MTA requires a license for public use of its logos, symbols, and other intellectual property; arrange that licensing before distributing this app.
