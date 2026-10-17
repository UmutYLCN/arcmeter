# AI Quota Widget

A local macOS desktop WidgetKit widget for Claude, Codex, and Antigravity (`agy`). Both small and medium widgets show Claude, Codex, agy Gemini, and agy Claude/GPT, with separate **5-hour** and **weekly** percentages, usage bars, and relative reset times for every scope. An asterisk marks the limiting window. A projected run-out time appears in orange as **Out ~…** when quota-axi reports one; the host also shows its calendar date. **Lasts to reset** means the reported pace reaches the next reset, and **No forecast** means quota-axi cannot project exhaustion.

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
3. Search for **AI Quota Widget**, then drag its small or medium widget onto the desktop.
4. Keep the host app running. It refreshes immediately on launch and every five minutes; **Refresh** requests a new read. Clicking the widget opens the host app.

If the gallery has not discovered the app, run it once from Xcode, close and reopen the gallery, and search again. For a stable installed location, copy the built app to your user Applications folder and launch that copy. Replacing a build can require removing and re-adding the widget.

A closed host window does not quit the process; reopen the app to show its window. Quitting the app or sleeping the Mac pauses reads. WidgetKit schedules display updates and can delay them; it is not a continuous background polling service. After 30 minutes without fresh data, the widget shows **STALE**. Missing or unreadable snapshots show all providers with **No data** and an instruction to open the app. Provider-side stale data is also marked stale. An omitted provider, unknown scope, failed authorization, or unmeasurable limit is never represented as 0% or 100%.

Claude reads always include `--allow-keychain-prompt`. If Claude reports **authorization needed**, follow the host app's hint: run `/usr/local/bin/quota-axi --provider claude --allow-keychain-prompt` in Terminal, re-authorize if needed, approve Keychain access with **Always Allow**, and refresh. A whole-command or decoding failure retains the last successful snapshot and its original timestamp, and displays an error in the host app.

## Additional local checks

After building, `Scripts/preview.sh` renders both widget sizes with the captured reading, stale data, missing data, and Claude authorization required to `DerivedData/Previews/`.

After launching the host and waiting for its first successful refresh, `Scripts/verify-sandbox.sh` builds an ad-hoc signed sandbox probe with the extension's exact entitlements. It checks that the shared snapshot contains all three providers, can be read, and cannot be opened for writing. This does not place a widget on the desktop; add the widget from the gallery to complete the interactive check.

## Local data and signing

The host runs quota-axi by absolute executable path, without a shell, with a fixed system/Homebrew PATH. It requests only Claude, Codex, and agy. Each read has a 90-second deadline. The host must remain unsandboxed so quota-axi can use its existing credential sources, Keychain approval, and vendor session refresh.

The host atomically writes a compact, account-free snapshot to:

```text
~/Library/Application Support/AIQuotaWidget/snapshot.json
```

The directory is created with user-only permissions; the file is user-readable and writable only. The sandboxed widget has a read-only [home-relative temporary exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html) for that exact file in `Config/Widget.entitlements`. It resolves the real home through `getpwuid`, rather than using the sandbox container home. There is no App Group or provisioning profile. This is a local development arrangement; App Store distribution would require revisiting the sharing and signing setup.

The decoder consumes schema version 5's `quotaSemantics.effectiveAvailability` and `runway` data (`exhaustion[]` is quota-axi's human-readable output rendering). It respects scope status, source freshness, and duplicate window IDs. Both window values come from that scope's `boundedBy` windows; agy Gemini and agy Claude/GPT never share each other's meters. Duplicate windows use the tightest reading and its reset. Untrusted or missing windows show a dash, never a fabricated percentage. Provider-side stale window values remain labeled stale and never display a current exhaustion forecast. Old snapshots remain readable until the first refresh supplies both windows. Unknown quota-axi schema versions fail visibly instead of guessing percentages. “Out” is a quota-axi projection, not a guarantee; the widget does not calculate its own usage forecast. Percentages describe remaining quota, not quota used.

There is no menu-bar component, remote service, telemetry, notification permission, or launch-at-login configuration.
