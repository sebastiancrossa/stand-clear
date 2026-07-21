# Stand Clear MVP

Stand Clear is a macOS menu bar app for checking nearby NYC subway arrivals at a glance.

## Required behavior

- Ask for location permission only to determine the nearest subway station.
- Keep location processing on device.
- Fetch live arrivals from the MTA public GTFS-Realtime subway feeds.
- Show the nearest station, distance, route, direction, destination, and ETA.
- Toggle each arrival independently between floored whole minutes and a `minutes:seconds` countdown.
- Open the direction-and-line picker first during onboarding, with every option unselected.
- Require at least one direction and one line before showing arrivals.
- Let the user choose northbound and/or southbound service and remember that choice.
- Let the user choose from the complete subway route catalog and remember which lines appear.
- Let the user pin one route-and-direction pair from an arrival row and remember it across launches.
- Show the pinned route, direction arrow, and next arrival as a `minutes:seconds` countdown directly in the menu bar.
- Follow the nearest station, advance immediately to the next matching train at zero, and show `--:--` when no upcoming matching arrival is available.
- Keep counting cached future arrivals when an MTA feed is temporarily unavailable.
- Let the user replace a pin from another arrival row or remove it from the active row or footer.
- Clear the pin when its route or direction is removed from the saved filters.
- Refresh automatically and expose a manual refresh action.
- Remain a menu-bar-only app with no Dock icon.

## Visual direction

- Compact black arrival board inspired by Closing Doors.
- Large, colored subway route bullets.
- Strong white typography, generous spacing, and simple direction arrows.
- Separate, selectable northbound and southbound direction controls.
- A direction-and-line picker state and an arrivals state.

## Out of scope for the MVP

- Trip planning, maps, buses, PATH, service alerts, push notifications, multiple pins, station-specific pins, and App Store distribution.
