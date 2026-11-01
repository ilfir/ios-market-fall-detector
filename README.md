# ios-market-fall-detector

**Index Watch** is an iPhone app that watches the S&P 500 and other major US stock indices during market hours.
It notifies you when a drop goes past thresholds you choose.

> Informational alerts only, not investment advice. Market data may be delayed.

---

## Features

- **Four detectors.** Each one has its own on/off switch and its own percentage:

  | Detector | Fires when… | Default |
  |---|---|---|
  | **Daily Fall** | the index is down at least X% from the previous trading day's close | 2.0% (on) |
  | **3-Month Drop** | the index is at least X% below its highest close of the last 3 months (63 trading days) | 7.0% (on) |
  | **6-Month Drop** | …below its highest close of the last 6 months (126 trading days) | 10.0% (on) |
  | **1-Year Drop** | …below its highest close of the last 12 months (252 trading days) | 15.0% (off) |

- **Indices:** S&P 500, Dow Jones and Nasdaq Composite are on by default. Russell 2000 and Total US Market are optional.
  ETF proxies (SPY, DIA, QQQ, IWM, VTI) can be used instead of the index values.
- **Check interval:** every **15 or 30 minutes**, 9:30 am – 4:05 pm ET on trading days. Weekends, NYSE holidays and
  early closes are skipped.
- **No alert spam:**
  - each detector alerts once when it crosses its threshold;
  - it alerts again only if the drop deepens by a configurable step (default 1 percentage point);
  - it re-arms after the market recovers. The daily detector also re-arms every new trading day.
  - If several detectors fire in the same check, you get **one** grouped notification.
- **Notification actions:** *View* and *Snooze today*.
- **Screens:**
  - **Market:** live dashboard with price, today's change, a 3-month sparkline, and a status light per detector
    (🔴 threshold reached · 🟡 within 1 pp · 🟢 OK · ⚪ off).
  - **Alerts:** history of the last 90 days.
  - **Settings:** detectors, interval, indices, alert options, data source.
- **Data sources:** Yahoo Finance (free, no key), Twelve Data (API key, stored in the iOS Keychain),
  or **Demo data** (offline, always shows a drop, so you can try alerts any time).

See [DESIGN.md](DESIGN.md) for the full design, including the planned backend for guaranteed check timing.

---

## Project layout

```
App/                        SwiftUI iOS app (iOS 16+)
  IndexFallDetectorApp.swift  app entry, background refresh hook
  AppModel.swift              app state, runs checks, foreground timer, schedules background refresh
  Services/                   NotificationService, BackgroundScheduler (BGTaskScheduler), KeychainService
  Views/                      Dashboard, Settings, Alert History, Onboarding
  Assets.xcassets/            app icon
FallDetectorKit/            Swift package with all the logic (no UIKit; builds and tests on macOS)
  Sources/DetectorCore/       models, DetectorEngine, AlertDeduplicator, MarketCalendar, AlertFormatter
  Sources/MarketData/         Yahoo / Twelve Data / Mock providers, MonitorRunner (fetch → evaluate → dedupe → persist)
  Sources/fdk-check/          command-line tool: one live check, printed to the terminal
  Tests/DetectorCoreTests/    XCTest suite (28 tests)
  scripts/run-tests.sh        runs the tests with only the Command Line Tools (no Xcode)
Config/
  Base.xcconfig               shared build settings (committed)
  Local.xcconfig.example      template for your personal signing settings
project.yml                 XcodeGen spec; the .xcodeproj is generated, not committed
scripts/make-icon.swift     redraws the app icon
DESIGN.md                   design document
```

---

## Requirements

- macOS with **Xcode 15 or newer** (developed with Xcode 27.2). An iOS Simulator runtime is needed to run in the
  Simulator: Xcode → Settings → Components.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple ID added to Xcode (Xcode → Settings → Accounts) to install on an iPhone. A free account works.
- An iPhone on iOS 16 or newer.

---

## Setup

1. **Clone the repo:**

   ```bash
   git clone https://github.com/ilfir/ios-market-fall-detector.git && cd ios-market-fall-detector
   ```

2. **Create your personal signing config.** The file is git-ignored, so your team ID never gets committed:

   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   Edit `Config/Local.xcconfig`:
   - `DEVELOPMENT_TEAM`: your Team ID. Find it in Xcode → Settings → Accounts, or on
     developer.apple.com → Membership.
   - `PRODUCT_BUNDLE_IDENTIFIER`: any unique reverse-DNS ID, e.g. `com.yourname.IndexFallDetector`.

3. **Generate the Xcode project and open it:**

   ```bash
   xcodegen generate && open IndexFallDetector.xcodeproj
   ```

   Re-run `xcodegen generate` after you add or remove files or change `project.yml`.

---

## Run in the Simulator

Choose an iPhone simulator in Xcode and press **Run** (⌘R). Or from the terminal:

```bash
xcodebuild -project IndexFallDetector.xcodeproj -scheme IndexFallDetector -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Background refresh never runs in the Simulator. Foreground checks and notifications do.

## Install on your iPhone

1. Connect the iPhone with a cable, unlock it, and tap **Trust This Computer**.
2. Turn on **Developer Mode:** Settings → Privacy & Security → Developer Mode, then restart. The switch only appears
   after the phone has been connected to a Mac running Xcode.
3. In Xcode, pick your iPhone as the run destination and press **Run**. Or from the terminal:

   ```bash
   xcrun devicectl list devices
   ```

   ```bash
   xcodebuild -project IndexFallDetector.xcodeproj -scheme IndexFallDetector -destination 'id=<DEVICE_UDID>' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
   ```

   ```bash
   xcrun devicectl device install app --device <DEVICE_UDID> build/DerivedData/Build/Products/Debug-iphoneos/IndexFallDetector.app
   ```

4. The first time only, trust the developer profile on the phone: Settings → General → **VPN & Device Management**
   → your *Apple Development* entry → **Trust**.
5. Open **Index Watch** and tap **Enable Notifications**.

**For reliable background checks:** keep Background App Refresh on for the app (Settings → General → Background App
Refresh) and don't force-quit it from the app switcher.

### Free vs. paid Apple developer account

| | Free Apple ID | Apple Developer Program ($99/yr) |
|---|---|---|
| Install on your own iPhone | ✅ | ✅ |
| App keeps working for | **7 days**, then reinstall from Xcode (settings are kept) | 1 year |
| Background checks + local notifications | ✅ | ✅ |
| Time-sensitive notifications (break through Focus) | ❌ | ✅ (re-enable the entitlement in `project.yml`) |
| Push from a backend (guaranteed 15-min checks, DESIGN.md Phase 2) | ❌ | ✅ |
| TestFlight / sharing | ❌ | ✅ |

---

## Using the app

- **Market tab:** pull down or tap ↻ to check now. The header shows the market status and the last and next check times.
- **Settings tab:**
  - **Detectors:** turn each one on or off and set its percentage (0.1–50%).
  - **Checking:** 15 or 30 minutes; *Market hours only*.
  - **Indices:** choose which ones to watch.
  - **Alerts:** re-alert step, snooze for the rest of today, *Send test notification*.
  - **Data:** data source, Twelve Data API key, ETF proxies.
  - **Maintenance:** *Reset alert memory* makes detectors that are already past their threshold alert again.
- **Alerts tab:** past alerts grouped by day; *Clear* removes them.

To see an alert immediately (for example on a weekend), switch **Settings → Data source → Demo data** or tap
**Send test notification**.

### Data sources

| Source | Key needed | Notes |
|---|---|---|
| Yahoo Finance | No | Free, unofficial endpoint with no guarantees. Fine for personal use. Real index values (^GSPC, ^DJI, ^IXIC…). |
| Twelve Data | Yes | Enter the key in Settings; it is stored in the iOS **Keychain**, never in code. The free plan covers ETFs only, so turn on *Use ETF proxies*. |
| Demo data | No | Generated on the device, with a −2.5% day. |

---

## Tests

With Xcode:

```bash
cd FallDetectorKit && swift test
```

Or open `FallDetectorKit/Package.swift` in Xcode and press ⌘U. If only the Command Line Tools are installed:

```bash
FallDetectorKit/scripts/run-tests.sh
```

The suite covers:
- detector math and threshold edges;
- the repeat-alert rules (escalation and re-arming);
- market hours, holidays, early closes and the daylight saving change;
- settings migration and clamping;
- notification text;
- a full monitor cycle, including persistence and fetch failures.

## Live check from the terminal

Runs one check against real data and prints every index against every detector, plus the notification it would send:

```bash
cd FallDetectorKit && swift run fdk-check --all
```

Options: `--source yahoo|twelveData|mock`, `--etf`, `--all`. For Twelve Data, pass the key through the environment
variable `TWELVE_DATA_API_KEY` rather than on the command line.

---

## How a check works

1. `MarketCalendar` decides whether a scheduled check should run (NYSE hours, America/New_York time zone).
2. `MonitorRunner` fetches the latest quote for each watched index, plus about 260 daily closes. The closes are
   cached once per day.
3. `DetectorEngine` calculates today's change against the previous close, and the drawdown from the trailing
   3-month, 6-month and 1-year highs.
4. `AlertDeduplicator` turns breaches into new alerts, using the saved alert state to avoid repeats.
5. The app posts one grouped local notification and saves the result and history (JSON files in Application Support).

The checks are triggered by:
- a timer while the app is open;
- when the app comes to the foreground;
- `BGAppRefreshTask` while the app is in the background. iOS decides the exact timing.

## Known limitations

- **Background timing is best-effort.** iOS may delay or skip background refreshes. Guaranteed 15-minute checks
  need the server + push design in DESIGN.md (Phase 2, paid developer account).
- **Yahoo Finance** is unofficial and may change without notice.
- **Holiday table:** the NYSE holidays in `MarketCalendar.swift` run through **2027** and need a yearly update.
- **Free-account installs** stop launching after 7 days; reinstall from Xcode.

## Roadmap

- Backend (serverless cron + APNs) for guaranteed check timing
- Home-screen widget
- Optional "new N-month low" mode next to "drop from N-month high"
- Real-time index data provider with a license

## License

Personal project, no license granted yet.
