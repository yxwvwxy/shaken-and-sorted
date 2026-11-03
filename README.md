# Shaken & Sorted

iPhone app to log cocktails you've drunk — name, ingredients, price, photo, place, and date — and see every ingredient you've had, sorted by kind.

Everything stays on your phone. No account, no server, no API key.

## Features

**Drinks**
- Timeline of every drink, newest first
- Fields: name, ingredients, price, date, place, photo
- Save as soon as **any one** of name, ingredients, photo, or place is filled
- Type a comma in an ingredient to start the next one
- Date defaults to today and can be changed
- Tap the photo to view it full screen; pinch or double-tap to zoom

**Scan from menu** (free, fully on device)
- Take or pick a photo of a menu, then swipe over words like a highlighter:
  **Name** (yellow), **Ingredients** (green), **Price** (pink)
- Pinch to zoom, two fingers to move, Undo / Clear to fix mistakes
- Ingredients are split on the menu's own punctuation (`,` `&` `and` `·` `/`), keeping names like `Brown Butter-Washed Rye` together
- ALL-CAPS menu text becomes Title Case; abbreviations such as XO or VSOP stay as printed
- The menu photo is saved as the drink's photo

**Places**
- Search a bar by name, or keep your own text
- Tap the place on a drink to open it in Apple Maps or Google Maps
- Pick a default map app in **Settings** (gear icon); long-press a place to choose another

**Ingredients tab**
- Every ingredient you've logged, grouped into categories:
  Whiskey, Gin, Vodka, Rum, Tequila & Mezcal, Brandy, Other Spirits, Liqueurs, Vermouth & Aperitifs, Bitters,
  Citrus & Acids, Sweeteners & Syrups, Juices & Fresh, Mixers & Bubbles, Dairy & Texture, Garnishes
- Sorted automatically from the name; tap an ingredient to fix its category or see which drinks used it

## Install it on your own iPhone

There is no App Store or TestFlight build, so you build it yourself with Xcode. It's free — a normal Apple ID is enough.

**You need**
- A Mac with [Xcode](https://apps.apple.com/app/xcode/id497799835) (tested with Xcode 26)
- An iPhone on iOS 17 or later, and a cable

**Steps**
1. Download this repo: **Code → Download ZIP** on GitHub (or `git clone`), then unzip it.
2. Double-click `ShakenAndSorted.xcodeproj` to open it in Xcode.
3. Sign in with your Apple ID: **Xcode → Settings → Accounts → +**.
4. In the left sidebar click the blue **ShakenAndSorted** project, pick the **ShakenAndSorted** target, and open **Signing & Capabilities**:
   - **Team**: choose your own name (Personal Team).
   - **Bundle Identifier**: change it to something unique, e.g. `com.yourname.shakenandsorted`.
     The one in the repo belongs to the author's team and won't sign for you.
5. Plug in your iPhone, unlock it, and tap **Trust** if asked.
6. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** (it restarts the phone).
7. In Xcode's top bar, choose your iPhone as the run destination and press **Run** (▶).
8. The first time, the iPhone says "Untrusted Developer". Go to **Settings → General → VPN & Device Management**, tap your Apple ID, and choose **Trust**. Then open the app.

**With a free Apple ID** the app stops opening after 7 days. Plug the phone in and press **Run** again to renew it — your drinks are kept.

To try it without a phone, choose any iPhone simulator in step 7 instead.

## Notes

- Data is stored on device with SwiftData. Deleting the app deletes your drinks.
- Menu text recognition uses Apple's Vision framework on the phone; nothing is uploaded.
- The app asks for photo and camera access only when you add a photo or scan a menu.
