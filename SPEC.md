# SubwayBar MVP

SubwayBar is a macOS menu bar app for checking nearby NYC subway arrivals at a glance.

## Required behavior

- Ask for location permission only to determine the nearest subway station.
- Keep location processing on device.
- Fetch live arrivals from the MTA public GTFS-Realtime subway feeds.
- Show the nearest station, distance, route, direction, destination, and ETA.
- Toggle each arrival independently between its rounded ETA and exact seconds countdown.
- Open the direction-and-line picker first during onboarding, with every option unselected.
- Require at least one direction and one line before showing arrivals.
- Let the user choose northbound and/or southbound service and remember that choice.
- Let the user choose from the complete subway route catalog and remember which lines appear.
- Refresh automatically and expose a manual refresh action.
- Remain a menu-bar-only app with no Dock icon.

## Visual direction

- Compact black arrival board inspired by Closing Doors.
- Large, colored subway route bullets.
- Strong white typography, generous spacing, and simple direction arrows.
- Separate, selectable northbound and southbound direction controls.
- A direction-and-line picker state and an arrivals state.

## Out of scope for the MVP

- Trip planning, maps, buses, PATH, service alerts, push notifications, and App Store distribution.
