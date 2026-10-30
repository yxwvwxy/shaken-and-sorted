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
- Save if **any one** of name, ingredients, photo, or place is filled
- Place search: first row = your exact text; below = Map results (name + address)
- Tap place → opens Google Maps (app if installed, otherwise the website)
- Scan from menu: photo a menu, circle one drink → name and ingredients filled in. Runs fully on device (Vision text recognition + Apple's on-device model on iOS 26 with Apple Intelligence; simple line rules otherwise). Free, no API key.

## Notes

- Data is stored on device with SwiftData (iCloud sync can be added later).
- Photo library permission is requested when you add a photo.
