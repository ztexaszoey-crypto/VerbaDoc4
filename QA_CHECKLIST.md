# QA Checklist — VerbaDoc TestFlight v1.0

**Version:** 1.0 (build target iOS 26 / X26.5)
**Owner:** QA Lead
**Test devices (minimum matrix):** iPhone 12 mini (smallest), iPhone 15 Pro (current flagship), iPhone SE 3rd gen (legacy-large + small)
**Build type:** Release with `PROD` xcconfig + production Supabase + production RevenueCat API key

> **Rule:** No Critical or High bug ships. Every Medium/Low bug goes to the backlog with a "Fix by" date.

---

## A. Account & Auth

| ID | Path | Pass criteria |
|---|---|---|
| A1 | Open app fresh install → tap "Sign Up" → enter valid email + 8+ char password | Account created; lands on onboarding within 5 sec |
| A2 | Same credentials → "Sign In" | Signed in; previous decks restored (if any) |
| A3 | Apple Sign-In button | Sheet appears, biometric prompt works, returns to app signed-in |
| A4 | Apple Sign-In cancelled mid-flow | State clean — no orphan token, no zombie UI |
| A5 | Wrong password 3x in a row | Generic error message, no enumeration, no rate-limit error spam |
| A6 | "Forgot Password" with valid email | "Check your email" confirmation; no leak of whether email exists |
| A7 | Sign Out with internet | Local data cleared, lands on SignInView, RevenueCat logged out |
| A8 | Sign Out offline (airplane mode) | Same behaviour — local clear completes; deferred to backend on reconnect |
| A9 | Delete Account from Settings → confirm dialog → tap "Delete" | Account gone within 7s; local SwiftData wiped; lands on SignInView; subscription cancelled through Apple |
| A10 | Cold launch signed-out, then sign in | No double-auth, no duplicate user objects in SwiftData |

## B. Onboarding

| ID | Path | Pass criteria |
|---|---|---|
| B1 | First-time user sees the SplashView → onboarding animation → tap "Get Started" | Tokens filed, lands on RootTabView in ≤2 sec |
| B2 | Paywall does NOT appear during onboarding | (rule from CAC brief: never block the path with money) |
| B3 | Notification permission is NOT requested during onboarding | (rule: permission requested AFTER first completed study session) |
| B4 | Skip-onboarding flow returns to onboarding on next launch if not completed | `hasSeenOnboarding` correctness |

## C. Upload & Document Creation

| ID | Path | Pass criteria |
|---|---|---|
| C1 | Upload 50 KB PDF | Preview shown, deck title editable, "Generate" CTA enabled |
| C2 | Upload 20 MB PDF (large, slow PDF) | Loader visible the whole time; no spinner flash-of-empty |
| C3 | Upload 1 photo from camera (debug device) | OCR finishes within 5 sec on 1-paragraph photo |
| C4 | Upload 1 photo from photo library | Photo picker permission requested ONCE; subsequent uses granted |
| C5 | Paste 200+ word text | Deck title defaults to first N words; "Generate" produces ≥5 cards |
| C6 | YouTube URL field → paste valid URL → tap "Extract" | Transcript pulled, deck created |
| C7 | YouTube invalid URL | Friendly error "couldn't find a transcript for this video" + retry |
| C8 | Empty deck title + tap Generate | Inline error "name your deck to continue" |
| C9 | Deck already exists with same title → Generate | Appends new cards to existing (or fresh? — verify) |
| C10 | Airplane mode → tap Generate | Graceful error: "AI is offline; we saved your deck — try Generate again when you reconnect" |

## D. AI Generation Quality

| ID | Path | Pass criteria |
|---|---|---|
| D1 | Generate flashcards from a science article | ≥5 cards, ≥0 cloze deletions, ≥0 "According to the…" preambles |
| D2 | Generate multiple-choice | 4 plausible options per question, exactly 1 correct, "why wrong" notes present |
| D3 | Generate open-answer questions | Each prompt requires analysis (not "What year did X happen?") |
| D4 | Generate study guide | Markdown renders; headers, tables, lists visible |
| D5 | Verify QualityValidator never silently drops flagged cards | (acceptance test: 0 verbatim copies in output) |
| D6 | "Generate" 10× in a row with same source | Free-tier counter decrements; at 0, paywall surfaces (not crash) |
| D7 | AI returns 5xx (provider down) → fallback path | Offline flashcard parser used; deck still created |
| D8 | AI returns malformed JSON | Friendly error, no crash, no stuck spinner |

## E. Study Sessions

| ID | Path | Pass criteria |
|---|---|---|
| E1 | Open a deck with 30 cards → tap "Study Now" | First card visible within 1 sec; rate card shows "X due today" |
| E2 | Tap "Show answer" → mark Correct | Card animates out, next card slides in, XP increments |
| E3 | Tap "Show answer" → mark Incorrect | Card stays, queue updated, XP not incremented |
| E4 | Complete full session | Session saved to SessionTracker; streak increments; analytics fires |
| E5 | Force-quit mid-session, relaunch | Apps opens on Resume screen; session state intact |
| E6 | Background app, return to it | Same as E5 |
| E7 | Toggle Reduce Motion (iOS Settings) | Card flips switch to fade (no spin) |
| E8 | Three sessions in one day | Day streak updates correctly across midnight in any timezone |

## F. Notifications

| ID | Path | Pass criteria |
|---|---|---|
| F1 | First study session complete → rationale overlay appears | Overlays on Home within 1 sec |
| F2 | Tap "Enable reminders" → OS prompt | Granted → SettingsView shows ON. Denied → SettingsView shows OFF + "open iOS Settings" link |
| F3 | `notif.permissionRequested` flagged → no further rationale overlay on next session | One-shot governance |
| F4 | Disable streak reminders in SettingsView | OS pending request `verba.evening` is removed within 5 sec |
| F5 | Disable all reminders in SettingsView | No notification fires at the next reminder hour |
| F6 | Enable all reminders, then trigger TestFlight "manual schedule" debug menu | Streak reminder actually fires (use simulator Debug → Trigger Notification) |
| F7 | Notification permission revoked via iOS Settings | NotificationManager.refreshPermissionStatus updates accordingly within 1 cold launch |

## G. Settings & Account Management

| ID | Path | Pass criteria |
|---|---|---|
| G1 | Open Settings tab → Pro banner shown | Free plan copy + upgrade CTA visible |
| G2 | Tap "Upgrade" | PaywallView presented (modal); user can dismiss |
| G3 | Settings list: streak reminders toggle | Toggles on/off, persists across cold launch |
| G4 | Settings list: study reminders toggle | Same as G3 |
| G5 | Settings list: slipping reminders toggle | Same as G3 |
| G6 | Privacy policy link | Opens in-app SafariViewController to https://verbadoc.app/legal/privacy |
| G7 | Terms of service link | Opens SafariViewController to https://verbadoc.app/legal/terms |
| G8 | Version number footer | Shows CFBundleShortVersionString + CFBundleVersion |
| G9 | Account: Sign Out | Dialog confirmation → local data cleared → SignInView |

## H. Paywall & Subscription

| ID | Path | Pass criteria |
|---|---|---|
| H1 | Free-tier counter at 0 → trigger AI generation | Paywall surfaces inline, not blocking the whole app |
| H2 | PaywallView → tap monthly → confirm in TestFlight sandbox | Receipt validated by RevenueCat, entitlement flipped within 3 sec |
| H3 | Manage Subscription in SettingsView when Pro | CustomerCenterView presented (Apple App Store management) |
| H4 | Receipt validation fails (simulated by RevCat dashboard setting entitlement to none) | Pro banner reverts to Free within 5 sec on next launch |
| H5 | Refund a sandbox subscription via App Store Connect | Pro status later shows Free without manual action |

## I. Performance

| ID | Path | Pass criteria |
|---|---|---|
| I1 | Cold launch on iPhone 12 mini | Home screen visible within 3 seconds |
| I2 | Warm app → Home from settings | Visible within 1 sec |
| I3 | LibraryView scroll with 30+ decks | 60 fps on iPhone 15 Pro, ≥30 fps on iPhone 12 mini |
| I4 | Study session with 100+ cards | Memory growth < 50 MB over 30 min session |
| I5 | Generate cards from 5 MB PDF | No hang > 10 sec, no crash |
| I6 | Background → foreground | No double-load of SwiftData, no orphan subscriptions |

## J. Accessibility

| ID | Path | Pass criteria |
|---|---|---|
| J1 | VoiceOver on Home | Each card, button, and tab is reachable and labelled |
| J2 | VoiceOver on a study card | Front label + "double-tap to reveal answer" hint |
| J3 | Dynamic Type at largest setting | No text clipped; no overlap |
| J4 | Color contrast (WCAG AA) at default text sizes | Verified via Xcode Accessibility Inspector |
| J5 | Reduce Motion → game animations | Game uses substitutes (no continuous spinning) |

## K. Offline Mode

| ID | Path | Pass criteria |
|---|---|---|
| K1 | Airplane mode → Library | Local decks visible |
| K2 | Airplane mode → open a deck, study | Full session works against local study items |
| K3 | Airplane mode → tap "Generate" | Friendly error; user can retry |
| K4 | Airplane mode → Sign out | Sign-out works; nothing pending |
| K5 | Reconnect after offline session | CloudSync resumes in background; no duplicate user actions |

## L. Privacy & Security

| ID | Path | Pass criteria |
|---|---|---|
| L1 | PrivacyInfo.xcprivacy filled | Verify text 100% accurate |
| L2 | Camera permission requested ONCE, no spam | (Camera usage description accurate) |
| L3 | Photo library limited permission selected | Only picked photos visible, photo library isn't walked |
| L4 | Tokens stored in Keychain | Verify via device console: `security dump-keychain` |
| L5 | No PII in AnalyticsManager log | grep the events.jsonl file — no raw user IDs |

## M. Edge Cases & Resilience

| ID | Path | Pass criteria |
|---|---|---|
| M1 | Locale: switch device language to Spanish, restart | App still launches, English fallback for strings |
| M2 | Date change: pull system clock back 1 day | Streak correctly rolls back |
| M3 | Time zone change: cross time-zone mid-day | Streak updates correctly |
| M4 | Low storage (< 200 MB free) | Audit logs compress correctly; no infinite growth |
| M5 | Very long deck title (200 chars) | Truncates with ellipsis; doesn't break layout |
| M6 | Two devices signed in to same account | Last-write-wins semantics; no data corruption |
| M7 | Dark mode (if supported) | All text legible, no glaring white cards |

---

## Bug Template (paste every bug here)

```
---
BUG #____
Title:           <short subject line>
Severity:        Critical / High / Medium / Low
Reproducible:    Always / Sometimes / Once / Unknown
Device:          <iPhone model + iOS version>
Build:           <TestFlight build # or commit>
Found in test:   <e.g. E5>
Reproduce steps:
  1.
  2.
  3.
Expected:        <what should happen>
Actual:          <what did happen>
Screenshot:      <attached>
Notes:           <links, related bugs>
Status:          Open / In Progress / Fixed / Verified / Won't Fix
---

```

---

## Sign-off

| Role | Name | Date | Sign |
|---|---|---|---|
| QA Lead |  |  |  |
| Engineering Lead |  |  |  |
| Product |  |  |  |
| Privacy review |  |  |  |

When every Critical and High item passes three consecutive runs on the test matrix above, the build is **READY FOR TESTFLIGHT PUBLIC BETA**.
