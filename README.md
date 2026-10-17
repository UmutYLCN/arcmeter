# Arcmeter

A local macOS desktop WidgetKit widget for Claude, Codex, and Antigravity (`agy`), in the **Orbit** design on a glossy black background. The Xcode project, scheme, and `AIQuotaWidget.app` bundle keep their original file names so the installed widget registration and shared snapshot keep working; the user-visible name is Arcmeter. The 5-hour window is the primary reading, drawn as a ring (half-circle on the small tile) with the remaining percentage inside; the weekly window sits below as `7d 33%` over ten thin segments, with its reset countdown. Rings, the half-circle, and weekly segments are white on a dim track; each indicator turns orange when its remaining quota drops below 20% and red below 10%, independently for the 5-hour and weekly windows. A `*` marks a limiting window that is running low (50% or less).

- **Small:** one provider per tile. Tap `›` to advance Claude, Codex, agy Gemini, agy Claude/GPT. WidgetKit has no swipe, so this is an interactive AppIntent button (macOS 14+); the current index is kept in the widget extension's own preferences.
- **Medium:** all four providers in a row, each with a 5h ring.
- **Large:** the same four providers in a 2x2 grid.
- **Orbit Ledger (separate large widget):** one row per provider with the 5h and 7d bars side by side.

Provider marks (Claude, Codex, Gemini, Antigravity) are vector shapes drawn in `Widget/ProviderMarks.swift`; the Antigravity mark follows the official full-color icon. Stale data shows a small clock badge on the affected provider (the widgets print no "Updated" text); a missing snapshot shows dashed rings with a crossed-out cloud and **No data**; a Claude authorization problem shows a lock and **Authorization needed**. The widget does not show run-out forecasts.

Requires macOS 15+, Xcode 16+ (tested with Xcode 26.3), and an existing `/usr/local/bin/quota-axi` installation. No package downloads, XcodeGen, Apple ID, or paid developer account are required. The project uses local ad-hoc signing; leave Signing Certificate set to **Sign to Run Locally** and do not select a development team.

## Build and test

From the repository root:

```sh
xcodebuild -project AIQuotaWidget.xcodeproj -scheme AIQuotaWidget \
  -configuration Debug -derivedDataPath DerivedData build
xcodebuild -project AIQuotaWidget.xcodeproj -scheme AIQuotaWidget \
  -configuration Debug -derivedDataPath DerivedData -destination 'platform=macOS' test
```

The shared app scheme builds and embeds the widget extension and runs the QuotaCore unit tests. The decoder is a small local Swift package in `QuotaCore/`; its tests also run with `swift test --package-path QuotaCore`. The fixture was captured from a real `quota-axi --json --allow-keychain-prompt` read on October 17, 2026. It contains only the three supported providers and has account keys removed.

Open `AIQuotaWidget.xcodeproj` in Xcode to edit or run. The checked-in project can be regenerated with `python3 Scripts/generate-project.py`, using only the Python standard library.

## Run and add to the desktop

```sh
open DerivedData/Build/Products/Debug/AIQuotaWidget.app
```

1. Let the first refresh finish. All four quota rows should appear in the host app.
2. Control-click the desktop and choose **Edit Widgets**.
3. Search for **Arcmeter** (small, medium, or large) or **Arcmeter Ledger** (large), then drag it onto the desktop.
4. Keep the host app running. It refreshes immediately on launch and every five minutes; **Refresh** requests a new read. Clicking the widget opens the host app.

If the gallery has not discovered the app, run it once from Xcode, close and reopen the gallery, and search again. For a stable installed location, copy the built app to your user Applications folder and launch that copy. Replacing a build can require removing and re-adding the widget.

A closed host window does not quit the process; reopen the app to show its window. Quitting the app or sleeping the Mac pauses reads. WidgetKit schedules display updates and can delay them; it is not a continuous background polling service. After 30 minutes without fresh data, the widget marks every provider with the clock badge. Missing or unreadable snapshots show all providers with **No data** and an instruction to open the app. Provider-side stale data is also marked stale. An omitted provider, unknown scope, failed authorization, or unmeasurable limit is never represented as 0% or 100%.

Claude reads always include `--allow-keychain-prompt`. If Claude reports **authorization needed**, follow the host app's hint: run `/usr/local/bin/quota-axi --provider claude --allow-keychain-prompt` in Terminal, re-authorize if needed, approve Keychain access with **Always Allow**, and refresh. A whole-command or decoding failure retains the last successful snapshot and its original timestamp, and displays an error in the host app.

## Additional local checks

After building, `Scripts/preview.sh` renders the small (all four provider frames), medium, large, and ledger layouts with the captured reading, stale data, missing data, and Claude authorization required to `DerivedData/Previews/`.

After launching the host and waiting for its first successful refresh, `Scripts/verify-sandbox.sh` builds an ad-hoc signed sandbox probe with the extension's exact entitlements. It checks that the shared snapshot contains all three providers, can be read, and cannot be opened for writing. This does not place a widget on the desktop; add the widget from the gallery to complete the interactive check.

## Local data and signing

The host runs quota-axi by absolute executable path, without a shell, with a fixed system/Homebrew PATH. It requests only Claude, Codex, and agy. Each read has a 90-second deadline. The host must remain unsandboxed so quota-axi can use its existing credential sources, Keychain approval, and vendor session refresh.

The host atomically writes a compact, account-free snapshot to:

```text
~/Library/Application Support/AIQuotaWidget/snapshot.json
```

The directory is created with user-only permissions; the file is user-readable and writable only. The sandboxed widget has a read-only [home-relative temporary exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) for that exact file in `Config/Widget.entitlements`. It resolves the real home through `getpwuid`, rather than using the sandbox container home. There is no App Group or provisioning profile. This is a local development arrangement; App Store distribution would require revisiting the sharing and signing setup.

The decoder consumes schema version 5's `quotaSemantics.effectiveAvailability` and `runway` data (`exhaustion[]` is quota-axi's human-readable output rendering). It respects scope status, source freshness, and duplicate window IDs. Both window values come from that scope's `boundedBy` windows; agy Gemini and agy Claude/GPT never share each other's meters. Duplicate windows use the tightest reading and its reset. Untrusted or missing windows show a dash, never a fabricated percentage. Provider-side stale window values remain labeled stale. Old snapshots remain readable until the first refresh supplies both windows. Unknown quota-axi schema versions fail visibly instead of guessing percentages. The decoder still carries quota-axi's `runway` fields, but no layout displays them. Percentages describe remaining quota, not quota used.

There is no menu-bar component, remote service, telemetry, notification permission, or launch-at-login configuration.
