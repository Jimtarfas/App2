# Shotfile: Screenshot Organizer

An iPhone app (SwiftUI, iOS 17+) that reads the text in your screenshots on the device, sorts them by kind, makes them searchable, and points out the ones that are out of date. It also turns Live Photos into stills and finds duplicate photos, similar shots and large videos.

The first version, "Phone Cleaner: Clean Up Photos", was rejected under guideline 4.3 (spam: too close to existing phone cleaners). Shotfile is the reworked app on the same App Store Connect record. See `marketing/app-review-reply.md` for the reply draft.

- **App Store name:** Shotfile: Screenshot Organizer (Apple ID 6826949859)
- **Bundle ID:** `com.cleanupphotos.app` (kept from the first version; never shown to users)
- **Team:** ZUCC9R4PP4
- **Minimum iOS:** 17.0 (iPhone only)

## How it works

| Piece | Where |
|---|---|
| Text recognition, sorting into kinds, written-date detection, out-of-date rules | `PhoneCleaner/Model/ScreenshotAnalyzer.swift` |
| Live Photo to still conversion (keeps date, location, favorite, albums) | `PhoneCleaner/Model/LivePhotoConverter.swift` |
| Scans, search, deleting, storage-freed total, free-plan allowance | `PhoneCleaner/Model/Cleaner.swift` |
| Vision feature prints for duplicate and similar photos | `PhoneCleaner/Model/SimilarityScanner.swift` |
| StoreKit 2: monthly and yearly (3-day free trial) plans in the "Shotfile Premium" group | `PhoneCleaner/Store/Store.swift` |
| Screens | `PhoneCleaner/Views/` (home, screenshot lists, detail and search in `ScreenshotViews.swift`) |

- **Kinds:** Codes & Logins, Tickets & Passes, Receipts & Orders, Chats, Maps & Directions, Posts & Links, Notes & Articles, Pictures. Each kind is scored with plain keyword and pattern rules on the recognized text, and ties go to the more specific kind.
- **Out of date:** one-time codes older than two days, and tickets whose written dates have all passed. Upcoming tickets are never flagged.
- **Caches:** recognized text is kept in `Caches/screenshot-text-v1.plist` and feature prints in `Caches/fingerprints-v2.plist`, keyed by photo and modification date. Screenshots are re-sorted on every launch, so rule changes apply to old screenshots without reading them again.
- **Free plan:** 20 deletions or conversions a day. Premium removes the limit.
- **Simulator:** Vision can't use the Neural Engine there. Text recognition runs on the CPU, and duplicate detection compares 16×16 thumbnails instead of feature prints (`#if targetEnvironment(simulator)` only).

## Build

```bash
xcodegen generate
open PhoneCleaner.xcodeproj
```

Keep build output outside `~/Desktop`, because codesign fails there. Archives go to `~/Builds/APP2`.

### Debug launch arguments

Debug builds accept `-route <screen>` to open a screen at launch. Values: `expired`; a kind (`codes`, `tickets`, …); `duplicates`, `similar`, `live`, `videos`, `swipe`, `settings`, `paywall`; `search:<text>`; `open:<word>` (the first screenshot containing a word); `shot:<kind>`. `-swipeDemo YES` leaves the swipe screen mid-swipe for screenshots. Any `@AppStorage` key can be overridden the same way, for example `-onboarded YES -introPaywallShown YES -freeDeletesUsed 0`.

## Test data and store assets

- `swift scripts/make-test-screenshots.swift <out-dir>` draws fictional screenshots: codes, passes, receipts, chats, directions, notes and posts.
- `swift scripts/make-live-photo.swift <image> <out-dir> <name> [date]` builds a Live Photo pair you can add with `xcrun simctl addmedia`.
- `swift scripts/make-test-media.swift <photos-dir> <out-dir>` makes similar bursts, duplicates and large videos.
- `swift scripts/make-icon.swift PhoneCleaner/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` draws the icon.
- `swift scripts/make-store-screenshots.swift marketing/screenshots/raw2 marketing/screenshots` frames the store screenshots at 6.9" and 6.5".

## Store listing and website

`marketing/listing.json` holds the name, subtitle, keywords, description, promotional text and review notes, and `marketing/aso.md` has the keyword research. `docs/` is published from the public repo `Jimtarfas/shotfile-site` to https://jimtarfas.github.io/shotfile-site/. Copy `docs/` there to update it.
