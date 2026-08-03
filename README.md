# Shaken & Sorted

iPhone app to log cocktails you've drunk — name, ingredients, photo, and place.

## Open in Xcode

1. Open `ShakenAndSorted.xcodeproj` in Xcode (double-click it in Finder under `~/Projects/Shaken & Sorted`).
2. Select your personal team under **Signing & Capabilities** (needed to run on a device).
3. Choose an iPhone simulator or your plugged-in iPhone.
4. Press **Run** (▶).

## First version

- Timeline list (newest first)
- Add / edit / delete a drink
- Fields: name, ingredients, photo, place
- Save if **name or at least one ingredient** is filled
- Place search: first row = your exact text; below = Map results (name + address)
- Tap place → opens Apple Maps

## Notes

- Data is stored on device with SwiftData (iCloud sync can be added later).
- Photo library permission is requested when you add a photo.
