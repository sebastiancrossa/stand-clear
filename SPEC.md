# Stand Clear MVP

Stand Clear is a macOS menu bar app for checking nearby NYC subway arrivals at a glance.

## Required behavior

- Ask for location permission only to determine the nearest subway station.
- Keep location processing on device.
- Fetch live arrivals from the MTA public GTFS-Realtime subway feeds.
- Show the nearest station, distance, route, direction, destination, and ETA.
- Persist a choice between floored whole minutes and a `minutes:seconds` countdown, with arrival-row ETAs remaining a shortcut for switching the setting.
- Open unified Settings first during onboarding, with every direction and line unselected.
- Reuse the same Settings controls for onboarding and later preferences, applying every change immediately without a Save or Apply action.
- Require at least one direction and one line before completing onboarding.
- Let the user choose northbound and/or southbound service and remember that choice.
- Let the user choose from the complete subway route catalog and remember which lines appear.
- Prevent removing the last selected route or direction after onboarding.
- Keep Settings accessible from a header gear even when location is unavailable.
- Default to a 420×610 Standard menu and offer a persisted 340×480 Compact menu.
- Fit at least eight complete 44-point arrival rows beneath one direction header in Compact mode when no feed warning is present.
- Keep route bullets, direction arrows, single-line truncated destinations, real-time labels, pin controls, and ETAs in Compact rows.
- Expose the full destination through pointer help and accessibility text when Compact truncates it.
- Let the user pin one route-and-direction pair from an arrival row and remember it across launches.
- Show the pinned route, direction arrow, and next arrival as a `minutes:seconds` countdown directly in the menu bar.
- Follow the nearest station, advance immediately to the next matching train at zero, and show `--:--` when no upcoming matching arrival is available.
- Keep counting cached future arrivals when an MTA feed is temporarily unavailable.
- Let the user replace a pin from another arrival row or remove it from the active row or footer.
- Clear the pin when its route or direction is removed from the saved filters.
- Refresh automatically and expose a manual refresh action.
- Remain a menu-bar-only app with no Dock icon.

## Visual direction

- Black arrival board inspired by Closing Doors.
- Standard mode retains large colored route bullets, strong white typography, generous spacing, and simple direction arrows.
- Compact mode reduces the menu frame and spacing without removing arrival information.
- Unified Settings and onboarding states with Appearance and Service sections.
- Separate, selectable northbound and southbound direction controls.

## Out of scope for the MVP

- Trip planning, buses, PATH, service alerts, push notifications, multiple pins, station-specific pins, themes, automatic density, granular appearance controls, and App Store distribution.
- Changes to the Live Map layout or menu-bar label/countdown.
