# Index Fall Detector — iOS App Design

**Status:** Draft v1 · **Date:** 2026-10-31 · **Platform:** iOS 17+ (SwiftUI)

---

## 1. Purpose

An iPhone app that watches major US stock market indices (S&P 500 plus other US indices) during market hours. It sends a push notification when a drop goes past a threshold the user sets.

The user configures up to four **detectors**. Each one can be turned on or off on its own and has its own percentage threshold:

| # | Detector | What it measures | Example threshold |
|---|----------|------------------|-------------------|
| 1 | **Daily Fall** | % change from the previous trading day's close to the current price | 2.0 % |
| 2 | **3-Month Drop** | % below the highest close of the last 3 months (rolling ~63 trading days) | 7.0 % |
| 3 | **6-Month Drop** | % below the highest close of the last 6 months (rolling ~126 trading days) | 10.0 % |
| 4 | **1-Year Drop** | % below the highest close of the last 12 months (rolling ~252 trading days) | 15.0 % |

The market is checked every **15 or 30 minutes** (user's choice). If **any** enabled detector fires for **any** watched index, the user gets a notification.

---

## 2. Goals & Non-Goals

### Goals
- Reliable, timely alerts during US market hours (9:30–16:00 ET, Mon–Fri, excluding NYSE holidays).
- Simple settings: one toggle and one percentage per detector.
- No repeated alerts for the same event (no spam).
- Clear in-app dashboard that shows the current state of each index versus each detector.

### Non-Goals (v1)
- Trading, brokerage integration, or investment advice.
- Individual stocks, crypto, or international indices (could come later).
- Tick-level, real-time streaming (15/30-minute checks are enough).

---

## 3. Watched Indices

"US market index" can mean more than one index, so the watch list is configurable. The S&P 500 is on by default.

| Index | Symbol (index) | ETF proxy (fallback) | Default |
|-------|----------------|----------------------|---------|
| S&P 500 | `^GSPC` / `SPX` | `SPY` | ✅ On |
| Dow Jones Industrial Average | `^DJI` | `DIA` | ✅ On |
| Nasdaq Composite | `^IXIC` | `QQQ` (Nasdaq-100) | ✅ On |
| Russell 2000 | `^RUT` | `IWM` | Off |
| Total US Market (Wilshire 5000) | `^W5000` | `VTI` | Off |

> **Licensing note:** Real-time *index* values (especially S&P) often need a paid data license. Many free and low-cost APIs give index data on a ~15-minute delay, or give only ETF prices. The design supports either mode: **index (delayed)** or **ETF proxy (near real-time)**. A 15-minute delay is fine for a 15/30-minute check interval.

---

## 4. Key Architecture Decision: How do we probe every 15/30 min?

**Problem:** iOS does **not** guarantee that a background app runs on a fixed schedule. `BGAppRefreshTask` runs when the system chooses: maybe every 15 minutes, maybe once every few hours, or almost never if the user rarely opens the app or Low Power Mode is on. The app can't reliably poll every 15 minutes on the device alone.

### Options

| Option | How it works | Reliability | Cost / Complexity |
|--------|--------------|-------------|-------------------|
| **A. On-device only** | `BGAppRefreshTask` fetches quotes and posts **local** notifications | ⚠️ Best-effort; can miss intraday drops | Free, simplest |
| **B. Lightweight backend + APNs** *(recommended)* | A scheduled cloud job runs every 15/30 min, checks the detectors, and sends a **remote push** through APNs | ✅ Reliable, exact schedule | Small (~$0–5/mo on serverless) |
| **C. Hybrid** | B is the main path; A runs on the device as a backup and refreshes the UI | ✅✅ | B + a little more |

**Recommendation: Option C (Hybrid)**, built in phases:
- **Phase 1:** Option A. Fast to build, works for personal use, and proves out the logic.
- **Phase 2:** Add the backend (B) for guaranteed timing. Keep the on-device check for UI refresh and as a backup.

The detection logic lives in a shared, pure module (Swift package for the app; ported or shared for the backend), so both paths behave the same way.

### Architecture diagram (Hybrid)

```
┌───────────────────────── iPhone ─────────────────────────┐
│                                                          │
│  SwiftUI Views ──► SettingsStore (SwiftData/AppStorage)  │
│       │                     │                            │
│       ▼                     ▼                            │
│  DashboardViewModel   DetectorEngine (pure Swift)        │
│       │                     ▲                            │
│       ▼                     │                            │
│  MarketDataService ─────────┘                            │
│       ▲                                                  │
│       │ BGAppRefreshTask (best-effort)                   │
│       │                                                  │
│  NotificationService (local + handles remote pushes)     │
│       ▲                                                  │
└───────┼──────────────────────────────────────────────────┘
        │ APNs push
┌───────┴──────────── Backend (Phase 2) ───────────────────┐
│  Scheduler (cron: */15 or */30, 9:30–16:15 ET, Mon–Fri)  │
│     → Fetch quotes + daily history (Market Data API)     │
│     → DetectorEngine (same rules)                        │
│     → Dedup store (last alert per user/index/detector)   │
│     → APNs sender                                        │
│  Device registry: APNs token + synced settings           │
│  e.g. Cloudflare Workers Cron / AWS Lambda+EventBridge / │
│       Firebase Cloud Functions + FCM→APNs                │
└──────────────────────────────────────────────────────────┘
```

---

## 5. Market Data

### Data needed per index
1. **Current price** (latest quote, can be delayed).
2. **Previous close** (for the Daily Fall detector).
3. **Daily closes for the last ~260 trading days** (for the 3M/6M/1Y rolling highs).

History only changes once a day. Cache it and refresh it once after each market close. Intraday checks only need the current quote, so each check is a single small API call.

### Candidate providers

| Provider | Indices? | Free tier | Notes |
|----------|----------|-----------|-------|
| Financial Modeling Prep | Yes (`^GSPC`) | Limited | Simple REST, has historical data |
| Twelve Data | Yes / ETFs | 800 req/day | Good for the free tier |
| Alpha Vantage | ETFs mainly | 25 req/day | Too limited for 15-min polling |
| Polygon.io | Indices (paid), ETFs | Delayed on free | High quality |
| Yahoo Finance (unofficial) | Yes | Free | No SLA, may break, ToS gray area. Prototyping only |

A `MarketDataProvider` protocol hides the provider, so switching is a config change:

```swift
protocol MarketDataProvider {
    func latestQuote(for symbol: String) async throws -> Quote
    func dailyHistory(for symbol: String, days: Int) async throws -> [DailyBar]
}
```

**API budget (on-device, 3 indices, 15-min interval):** about 27 checks/day × 3 quotes = ~81 calls, plus 3 history calls. That fits most free tiers. Batch endpoints (several symbols per call) cut this further.

---

## 6. Detection Logic

### Definitions
- `P` = current price
- `C_prev` = previous trading day's close
- `H_N` = highest daily close over the trailing window N (3M, 6M, 1Y), **including today's intraday price** if it is higher
- `dailyChange% = (P − C_prev) / C_prev × 100`
- `drawdown_N% = (H_N − P) / H_N × 100`

### Firing rules
| Detector | Fires when |
|----------|-----------|
| Daily Fall | `dailyChange% ≤ −threshold` |
| 3-Month Drop | `drawdown_3M% ≥ threshold` |
| 6-Month Drop | `drawdown_6M% ≥ threshold` |
| 1-Year Drop | `drawdown_1Y% ≥ threshold` |

> **Interpretation note:** I read "lowest for last N months drop" as **drawdown from the N-month high**, which is the usual way to measure a correction. Another option is a **"New N-month low"** mode, which fires when the price drops below the lowest close in the window. That could be a per-detector toggle (see Open Questions).

### Pseudocode

```swift
struct DetectorEngine {
    static func evaluate(index: IndexSnapshot,
                         settings: DetectorSettings) -> [DetectorHit] {
        var hits: [DetectorHit] = []

        if settings.daily.isEnabled {
            let change = (index.price - index.previousClose) / index.previousClose * 100
            if change <= -settings.daily.threshold {
                hits.append(.init(kind: .daily, value: change, threshold: settings.daily.threshold))
            }
        }

        for (kind, window) in [(.threeMonth, 63), (.sixMonth, 126), (.oneYear, 252)] {
            let cfg = settings[kind]
            guard cfg.isEnabled else { continue }
            let high = max(index.closes.suffix(window).max() ?? index.price, index.price)
            let drawdown = (high - index.price) / high * 100
            if drawdown >= cfg.threshold {
                hits.append(.init(kind: kind, value: -drawdown, threshold: cfg.threshold, reference: high))
            }
        }
        return hits
    }
}
```

### Alert deduplication (no spam)
A detector that stays "breached" would fire again on every check. To prevent that:

1. **Once per event per day:** keep `lastAlert[index][detector] = (date, level)`. Don't send the same detector for the same index again on the same trading day…
2. **…unless it gets meaningfully worse:** re-alert if the drop has deepened by at least the **escalation step** (default 1.0 percentage point, configurable). Example: Daily threshold 2% → alert at −2.1%, again at −3.1%, again at −4.1%.
3. **Drawdown detectors (3M/6M/1Y)** can stay breached for weeks. By default they alert **once when first crossed**, then only on escalation steps or after a **reset**. A reset happens when the drawdown recovers above `threshold − hysteresis` (default hysteresis 1 pp).
4. **Grouping:** if several detectors fire in the same check, send **one** combined notification.

---

## 7. Scheduling

| Setting | Values | Default |
|---------|--------|---------|
| Check interval | 15 min / 30 min | 15 min |
| Active window | Market hours only (9:30–16:00 ET) | On |
| Final check | 16:05 ET (catches the close) | On |
| Skip | Weekends and NYSE holidays (static calendar, updated yearly) | On |

- **On-device:** after each run, schedule the next `BGAppRefreshTaskRequest` with `earliestBeginDate = now + interval`, moved forward to the next market open if the market is closed. Also run a check every time the app comes to the foreground.
- **Backend:** cron in America/New_York time, e.g. `*/15 9-16 * * 1-5`, with a holiday/time guard in code.
- **Daylight saving time:** always calculate in `America/New_York`, never in UTC offsets.

---

## 8. Notifications

### Permission
Ask for notification permission (`.alert, .sound, .badge`) during onboarding, after a short explanation screen. Optional: `.timeSensitive` interruption level (needs the Time Sensitive Notifications capability), so alerts get through Focus modes.

### Content examples
**Single hit**
> 📉 **S&P 500 down 2.4% today**
> 5,612.30 (−137.85) · Daily threshold: 2.0%

**Drawdown hit**
> 📉 **Nasdaq 10.3% below 6-month high**
> 17,250.10 vs high 19,231.00 · Threshold: 10.0%

**Grouped**
> 📉 **Market drop alert (3 triggers)**
> S&P 500: −2.4% today, −7.8% from 3M high · Dow: −2.1% today

- Tapping a notification opens the Dashboard with that index expanded.
- Category actions: **"Snooze today"** (mute the rest of the day), **"View"**.
- `threadIdentifier` = index symbol, so notifications are grouped by index in Notification Center.

---

## 9. Screens / UX

### 9.1 Dashboard (home)
```
┌─────────────────────────────────────┐
│  Market Watch          ⚙︎            │
│  Last checked 10:45 ET · Next 11:00 │
├─────────────────────────────────────┤
│  S&P 500            5,612.30        │
│  Today      −2.40%  🔴 (≥2.0%)      │
│  vs 3M high −7.80%  🔴 (≥7.0%)      │
│  vs 6M high −8.10%  🟢 (≥10.0%)     │
│  vs 1Y high −8.10%  🟢 (≥15.0%)     │
│  [sparkline chart ───────╲__]       │
├─────────────────────────────────────┤
│  Dow Jones          41,020.55  ...  │
│  Nasdaq             17,250.10  ...  │
├─────────────────────────────────────┤
│         [ Check now ]               │
└─────────────────────────────────────┘
```
- 🔴 breached · 🟡 within 1 pp of the threshold · 🟢 OK · ⚪︎ detector off
- Pull to refresh = manual check.
- Market status badge: Open / Closed / Holiday / Data delayed.

### 9.2 Settings
```
┌─────────────────────────────────────┐
│  ‹ Settings                         │
├── DETECTORS ────────────────────────┤
│  Daily Fall                 [ ON ]  │
│     Alert when down ≥  [ 2.0 ] %    │
│  3-Month Drop               [ ON ]  │
│     Below 3M high by ≥ [ 7.0 ] %    │
│  6-Month Drop               [ ON ]  │
│     Below 6M high by ≥ [10.0 ] %    │
│  1-Year Drop                [OFF ]  │
│     Below 1Y high by ≥ [15.0 ] %    │  (greyed when off)
├── CHECKING ─────────────────────────┤
│  Check every     ( 15 min | 30 min )│
│  Market hours only          [ ON ]  │
├── INDICES ──────────────────────────┤
│  S&P 500                    [ ON ]  │
│  Dow Jones                  [ ON ]  │
│  Nasdaq Composite           [ ON ]  │
│  Russell 2000               [OFF ]  │
│  Total US Market            [OFF ]  │
├── ALERTS ───────────────────────────┤
│  Re-alert if worse by    [ 1.0 ] pp │
│  Time-sensitive alerts      [ ON ]  │
│  Send test notification     ›       │
├── DATA ─────────────────────────────┤
│  Data source      Twelve Data   ›   │
│  API key          ••••••••      ›   │
│  Use ETF proxies            [OFF ]  │
└─────────────────────────────────────┘
```
**Input rules**
- Thresholds: 0.1–50.0 %, step 0.1. Use a decimal keypad and a stepper.
- Each detector toggle works independently ("check off one by one"). At least one detector and one index must stay on, or the app warns that monitoring is paused.
- Changes save right away and (Phase 2) sync to the backend.

### 9.3 Alert History
A list of past alerts (time, index, detector, value, threshold). Useful for tuning thresholds. Kept for 90 days.

### 9.4 Onboarding
1. What the app does → 2. Notification permission → 3. Pick indices → 4. Set thresholds (with sensible defaults) → Done.

---

## 10. Data Model (SwiftData)

```swift
enum DetectorKind: String, Codable, CaseIterable {
    case daily, threeMonth, sixMonth, oneYear
    var tradingDays: Int? { [.daily: nil, .threeMonth: 63, .sixMonth: 126, .oneYear: 252][self]! }
}

struct DetectorConfig: Codable {
    var isEnabled: Bool
    var threshold: Double          // percent, positive number
}

@Model final class AppSettings {
    var detectors: [DetectorKind: DetectorConfig]
    var intervalMinutes: Int       // 15 or 30
    var marketHoursOnly: Bool
    var watchedSymbols: [String]
    var escalationStep: Double     // pp, default 1.0
    var hysteresis: Double         // pp, default 1.0
    var useETFProxies: Bool
    var timeSensitive: Bool
}

@Model final class PriceHistory {     // cached daily closes
    @Attribute(.unique) var symbol: String
    var bars: [DailyBar]              // ~260 most recent
    var lastUpdated: Date
}

@Model final class AlertState {       // dedup
    var symbol: String
    var detector: DetectorKind
    var lastAlertDate: Date
    var lastAlertLevel: Double
    var isArmed: Bool                 // false until recovery past hysteresis
}

@Model final class AlertRecord {      // history screen
    var timestamp: Date
    var symbol: String
    var detector: DetectorKind
    var value: Double
    var threshold: Double
}
```
Store the API key in the **Keychain**, not in SwiftData.

---

## 11. Project Structure

```
IndexFallDetector/
├── App/
│   ├── IndexFallDetectorApp.swift      // BGTask registration, notification delegate
│   └── AppDelegate.swift               // APNs token (Phase 2)
├── Features/
│   ├── Dashboard/ (View, ViewModel, IndexCard, Sparkline)
│   ├── Settings/  (SettingsView, DetectorRow, IndexToggleList)
│   ├── History/   (AlertHistoryView)
│   └── Onboarding/
├── Core/                               // Swift Package: DetectorCore (pure, testable)
│   ├── DetectorEngine.swift
│   ├── AlertDeduplicator.swift
│   └── MarketCalendar.swift            // hours, holidays, ET tz
├── Services/
│   ├── MarketData/ (MarketDataProvider, TwelveDataProvider, FMPProvider, MockProvider)
│   ├── MonitorService.swift            // orchestrates one check
│   ├── BackgroundScheduler.swift       // BGTaskScheduler wrapper
│   ├── NotificationService.swift
│   └── KeychainService.swift
├── Persistence/ (SwiftData models)
└── Tests/
    ├── DetectorEngineTests.swift
    ├── DeduplicatorTests.swift
    └── MarketCalendarTests.swift
backend/ (Phase 2)
└── check-markets/ (cron handler, APNs sender, settings sync endpoint)
```

### One monitoring cycle (`MonitorService.runCheck()`)
1. If the market is closed (and it isn't the post-close check), stop and schedule the next run at market open.
2. Refresh `PriceHistory` if it's older than the last close.
3. Get the latest quotes for the watched symbols (batched).
4. `DetectorEngine.evaluate` for each index → hits.
5. `AlertDeduplicator.filter(hits)` → new or escalated hits only.
6. If there are any: send a grouped notification and save `AlertRecord`s.
7. Update the dashboard state and the widget timeline; schedule the next BG task.

---

## 12. Edge Cases

| Case | Handling |
|------|----------|
| API failure / rate limit | Retry once with backoff. Show a "Data stale" badge. Never alert based on stale data (> 2 intervals old) |
| Half trading days (e.g. day after Thanksgiving, 13:00 close) | Market calendar includes early closes |
| Market halt / circuit breaker | Quotes freeze; detectors still use the last price; no special handling needed |
| Very first launch (no history) | Fetch history right away; drawdown detectors show "Loading…" until it's ready |
| Bad tick / data glitch (e.g. −50%) | Sanity check: ignore changes > 25% in one interval unless confirmed on the next check |
| User changes a threshold mid-day | Reset `AlertState` for that detector so the new threshold is evaluated fresh |
| Notifications denied | Banner on the dashboard with a link to iOS Settings |
| Phone offline | Backend push still arrives when the phone reconnects (Phase 2) |

---

## 13. Testing Strategy
- **Unit tests** (DetectorCore): threshold edges (exactly equal), windows with fewer bars than needed, escalation and hysteresis sequences, DST transitions, holidays.
- **Replay tests:** feed historical days (e.g. 2020-03-16 −12%, 2022 bear market, 2024-08-05) through the engine and check that the alerts are what you'd expect.
- **MockProvider** with scripted prices for UI and integration tests.
- **Background task:** debug with `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"..."]` in LLDB.
- **Debug menu:** "Fire test alert", "Simulate −3% day", "Clear alert state".

---

## 14. Milestones

| Phase | Scope | Est. |
|-------|-------|------|
| **M1 – Core** | DetectorCore package + tests, MarketCalendar, MockProvider | 2–3 days |
| **M2 – App MVP** | Settings, Dashboard, one real data provider, foreground checks, local notifications | 3–4 days |
| **M3 – Background** | BGAppRefreshTask, dedup persistence, alert history | 2 days |
| **M4 – Polish** | Onboarding, sparklines (Swift Charts), widget, time-sensitive alerts | 2–3 days |
| **M5 – Backend** | Serverless cron + APNs, settings sync, device registration | 3–5 days |

---

## 15. Open Questions
1. **Which "US market index"?** Is the default set (S&P 500, Dow, Nasdaq) right, or did you mean one specific index such as Total Market/Wilshire 5000?
2. **Drawdown vs. new low:** should 3M/6M/1Y mean "X% below the period's high" (assumed here) or "X% below the period's *low*, i.e. a new low"?
3. **Personal use or App Store?** This decides whether the API key comes from the user (personal) or from your backend (distribution), and how much the data license matters.
4. **Phase 2 backend:** OK to add a small serverless backend for guaranteed 15-minute checks, or stay device-only?
5. Should alerts also go to Apple Watch (that happens automatically through iPhone mirroring) or other channels (email, SMS)?

---

*Disclaimer to show in the app: informational alerts only, not investment advice. Data may be delayed.*
