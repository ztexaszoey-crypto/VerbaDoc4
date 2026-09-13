# VerbaDoc — next steps (copy-friendly)

Written to disk because the chat response wouldn't select/copy.

> **Status: nothing has been compiled.** Every `xcodebuild` attempt this session
> failed because the shell could not spawn (`posix_spawn 'bash'` ENOENT).
> Everything here is statically reviewed, not verified. Run the command in
> section 9 yourself and paste the output back.

---

## 1. AI generation — the direct answer

**Nothing is wired.** No call site was changed this session (tutor chat, deck
generation, quiz generation, notes outline all still call what they called
before).

**`AIChatService.swift` does not exist in the project.** The advisor's sketch
was never added — it hardcoded both API keys and would have collided with your
existing Groq client. So "route it through `AIChatService.send(...)`" **cannot
be followed**. Absent as far as I can tell — but my file access this session was limited to
`Services/`, so **`Features/` was never searched**. Run these and trust the
output over my claim. Use `-w`: plain `grep AIProvider` is NOT empty, because
`AIProviderConfig` contains that substring.

```bash
grep -rnw 'AIChatService'  --include='*.swift' .
grep -rnw 'AIProvider'     --include='*.swift' .
grep -rnw 'AIServiceError' --include='*.swift' .
```

The real symbols:

```swift
let (answer, provider) = try await AIChatRouter.shared.send(
    system: "You are Verba, a friendly AI study tutor.",
    userPrompt: question
)
// provider is diagnostics only — never show it to the student.
```

Types: `AIChatRouter` · `AIChatProvider` · `AIChatError` · `AIProviderConfig`

---

## 2. THE BLOCKER — wire the Groq key first

`AIProviderConfig.defaults` references the literal string `GROQ_API_KEY`, and
`orderedCandidates` filters unconfigured providers out. Without both of these
the router is **NVIDIA-only and the failover never executes** — you would see
the 429 disappear and wrongly conclude it was fixed.

**`project.pbxproj` — add to BOTH Debug and Release build settings:**

```
INFOPLIST_KEY_GROQ_API_KEY = $(GROQ_API_KEY);
```

**`Config.xcconfig` (gitignored):**

```
GROQ_API_KEY = gsk_...your key...
NVIDIA_API_KEY = nvapi-...your key...
```

### Then you MUST wire the xcconfig in — or the key is silently blank

`$(GROQ_API_KEY)` only expands if `Config.xcconfig` is set as the **Base
Configuration**. Without this step everything below looks correct and the key
is empty, which is the exact silent failure this section exists to prevent.

In Xcode: select the **VerbaDoc project** (the project, not the target) →
*Info* tab → **Configurations** → set **Config.xcconfig** as the Base
Configuration for **both Debug and Release**.

Both `INFOPLIST_KEY_...` lines go on the **VerbaDoc target's** Build Settings,
in **Debug and Release** — that is where
`INFOPLIST_KEY_NSCameraUsageDescription` already lives. (Project level would
also work unless the target overrides it; the target is the clearer place.)

Finally, confirm the Groq key your existing client uses is the *same* value,
and repoint that old code at this one key name instead of keeping two copies.

**Verify the wiring actually took** — the failure mode above is silent, so
check it rather than assuming:

Put this somewhere that actually runs at launch — `.onAppear` of the root view,
or `VerbaDocApp.init()` — not at file scope:

```swift
// The exact gate `AIChatRouter.orderedCandidates` uses, so this tests the real
// path rather than a raw plist read. Note the placeholder prefix — a key left
// as `gsk_YOUR...` counts as NOT configured.
print(APIKey.isConfigured(infoPlistKey: "GROQ_API_KEY",
                          placeholderPrefixes: ["gsk_YOUR"]))
print(NVIDIAAPIKey.isConfigured)
```

Both must print `true`. A `false` means the Base Configuration isn't set (or the
xcconfig isn't attached to that configuration) — not that the key is wrong.

---

## 3. Why "AI generation hit a snag" appears

That string is `FriendlyErrorMapper.Context.aiGeneration.defaultMessage`, and it
is reachable from **four** places, not one:

1. the final `return context.defaultMessage`
2. `mapURLError`'s `default:`
3. `mapCocoaError`'s `default:`
4. `mapPOSIXError`'s `default:`

So seeing it does **not** prove "not a network error" — it only rules out the
three curated connectivity codes.

**Likely real cause:** `FriendlyErrorMapper` knows nothing about `AIChatError`
or `NVIDIAError`. They are not `AuthService.AuthError`, so every branch misses
them and they fall through to `context.defaultMessage`:

- a 429 → "AI generation hit a snag"
- a retired model ID → "AI generation hit a snag"
- every provider failing → "AI generation hit a snag"

That is exactly why it's hard to diagnose from the outside — the mapper throws
away the only information that mattered.

**Do not chunk the notes yet.** That is a fix for an unmeasured problem, and
chunking already exists in `TextChunker` (paragraph → sentence → word, hard
character cap) plus `StudyGenContext.sample` for coverage. Instrument first.

---

## 4. Patch: FriendlyErrorMapper.swift

Three edits. (I couldn't reach this file, so apply by hand.)

### 4a. Replace `message(for:in:)` with this COMPLETE function

⚠️ **Do not add a second `let nsError`.** The function already declares one
further down. Adding another is `invalid redeclaration of 'nsError'` — a hard
compile error. Below is the **complete, paste-ready function**: the declaration
is MOVED up (not duplicated), so the log also fires for the
`AuthService.AuthError` early-return path. That matters because a
connectivity-flavoured `errorDescription` in AuthService is one of the three
candidate root causes — logging only after that early-return would hide it.

`as NSError` is a total, side-effect-free conversion, so evaluating it earlier
changes no behaviour.

⚠️ **Replace ONLY this one function.** Do **not** paste it over the whole enum.
You have already edited `mapCocoaError` (the `NSCocoaError.Code.*.rawValue`
change), and overwriting the file would silently revert that. Your
`mapCocoaError` / `mapPOSIXError` / `mapURLError` edits are untouched by this.
The version below also drops the original explanatory comments.

⚠️ **One behaviour change, on purpose.** The `-34018` check gains a domain test
(`nsError.domain == NSOSStatusErrorDomain`). That is a real change, not a tidy-up:
an error that previously matched the bare code with a *different* domain will now
fall through to the domain dispatch. That is the intended fix — the branch was
only ever meant to catch the Security-framework entitlement error.

```swift
static func message(for error: Error, in context: Context) -> String {
    // MOVED up from below (it used to sit just above the -34018 check).
    let nsError = error as NSError

    #if DEBUG
    // Domain + code only — never the message, which can carry a URL.
    print("[FriendlyErrorMapper] domain=\(nsError.domain) code=\(nsError.code) ctx=\(context)")
    #endif

    // 1. Auth domain: has its own localised messages from
    //    AuthService.AuthError — pass through.
    if let authError = error as? AuthService.AuthError,
       let desc = authError.errorDescription {
        return desc
    }

    // 2. Top-level OSStatus catch for Security-framework entitlement errors.
    //    Domain-checked as well as code-checked: -34018 is
    //    errSecMissingEntitlement in NSOSStatusErrorDomain, and matching the
    //    bare code could misroute an unrelated error that shares it.
    if nsError.domain == NSOSStatusErrorDomain, nsError.code == -34018 {
        return "Storage permissions changed. Please reinstall VerbaDoc."
    }

    if nsError.domain == NSURLErrorDomain {
        return mapURLError(code: nsError.code, context: context)
    }
    if nsError.domain == NSCocoaErrorDomain {
        return mapCocoaError(code: nsError.code, context: context)
    }
    if nsError.domain == NSPOSIXErrorDomain {
        return mapPOSIXError(code: nsError.code, context: context)
    }

    // 3. Everything else: straight default. This is the contract.
    return context.defaultMessage
}
```

### 4b. Stop the `.network` default from lying

*(A single switch arm — replace only the existing `case .network:` inside
`Context.defaultMessage`. Do not paste this as a standalone file.)*

```swift
case .network:
    // NOT a connectivity claim. `.network` is the blanket context most call
    // sites use, so anything unrecognised lands here — decode failures and
    // non-URLError transport errors included. Connectivity copy now comes
    // ONLY from mapURLError's three genuine connectivity codes.
    return "Something went wrong. Try again in a moment."
```

### 4c. Add the missing URLError codes (none of these are connectivity)

*(Switch arms — add these inside `mapURLError`. Not a standalone file.)*

```swift
case NSURLErrorBadServerResponse,                 // -1011
     NSURLErrorCannotParseResponse,               // -1017
     NSURLErrorHTTPTooManyRedirects,              // -1007
     NSURLErrorResourceUnavailable,               // -1008
     NSURLErrorRedirectToNonExistentLocation:     // -1010
    return "The server had a problem with that request. Try again in a moment."

// -1013 / -1012 are AUTH, not server, and `ErrorPresentation` classifies them
// as `.auth` (lock icon, "sign out and back in"). Keep the copy consistent or
// the banner and the message will contradict each other for the same error.
case NSURLErrorUserAuthenticationRequired,        // -1013
     NSURLErrorUserCancelledAuthentication:       // -1012
    return "Your sign-in needs to be refreshed. Sign out and back in."

case NSURLErrorAppTransportSecurityRequiresSecureConnection:  // -1022
    return "Couldn't establish a secure connection. Try again."
```

The doc does not show the current `mapURLError` switch, so you cannot verify the
above by eye. If the compiler reports a duplicate pattern, delete the older arm
it points at.

### 4d. Fix the copy that now contradicts the banner

*(A switch arm — replace the existing `NSURLErrorCannotFindHost` /
`NSURLErrorCannotConnectToHost` / `NSURLErrorDNSLookupFailed` arm inside
`mapURLError`.)*

`ErrorPresentation` classifies `-1003` / `-1004` / `-1006` as `.server`, so the
banner shows a server icon and the hint *"This one's on us — try again in a
moment."* But the mapper's **existing** copy for those same three codes says
*"Couldn't reach the server. **Check your connection** and try again."*

A wrong host, a paused Supabase project, or a DNS failure is not the user's
connection. Change that group's copy so message and banner agree:

```swift
case NSURLErrorCannotFindHost,
     NSURLErrorCannotConnectToHost,
     NSURLErrorDNSLookupFailed:
    return "Couldn't reach the server. Try again in a moment."
```

Without this, the message blames the connection while the banner says it isn't
the connection.

One acceptance worth knowing: `.server` is marked retryable, so the banner will
offer "retry" for a wrong host or a paused project. That's acceptable — a paused
Supabase project does resume — but it will fail identically until the host or
project is fixed.

No separate step is needed for `-34018` — see 4a.

### 4e. Fix the header comment

It currently says call sites should pass `in: .network | .auth | .upload`. You
can't OR contexts, and that line is what pushed callers to `.network` on the
sign-in path. Say: pass the context matching what the user just attempted.

---

## 5. Read your own log — what each line means

| Log shows | Meaning |
|---|---|
| `NSURLErrorDomain -1009` | Genuinely offline. Mapper was right. |
| `NSURLErrorDomain -1001` / `-1004` | Network fine — server slow, wrong host, or paused Supabase project. |
| `NSURLErrorDomain -1011` / `-1017` | Server returned garbage (5xx via proxy, non-HTTP response). |
| `NSURLErrorDomain -1022` | ATS blocked it. **Almost always an `http://` URL — check the Supabase URL.** |
| `Swift.DecodingError` | Response shape doesn't match the model. Very common with a wrong project URL. Match on the **domain name**, not a numeric code — `DecodingError` has no fixed NSError codes, so don't go hunting for one. |
| A custom domain | The mapper's default is the bug; AuthService isn't wrapping. |

---

## 6. New files created this turn

| File | What it is |
|---|---|
| `Services/ErrorPresentation.swift` | `ErrorKind` + `ErrorPresentation` — the single classifier. Copy still owned by `FriendlyErrorMapper`, except for AI kinds a user can act on. |
| `Design/VerbaErrorBanner.swift` | The ONE error banner + `.errorBanner(presentation:onRetry:onDismiss:)`. |

### Adopt it — otherwise it's dead code

**As things stand right now, the consolidation is NOT delivered.** These two
files are referenced by nothing except their own `#Preview`, so the three
generic strings are still live in the app. It becomes the ONE banner the moment
a screen actually calls `.errorBanner(...)`.

```swift
// in a view model (ObservableObject)
@Published var error: ErrorPresentation?

// on failure — `error` here is the catch binding, not the property
func generate() async {
    do {
        try await somethingThatThrows()
    } catch {
        self.error = ErrorPresentation(error, in: .aiGeneration)
    }
}

// in the view — `onRetry` is a plain `() -> Void`, NOT async
MyScreen()
    .errorBanner(presentation: viewModel.error, onRetry: viewModel.reload)

// If reload is async, wrap it — and NAME the parameter. A bare trailing
// closure binds to the LAST parameter, which is `onDismiss`, so your retry
// would silently become the dismiss action and the retry button would never
// appear. This is the one place a shortcut is wrong here:
// MyScreen().errorBanner(
//     presentation: viewModel.error,
//     onRetry: { Task { await viewModel.reload() } }
// )
```

---

## 7. Capy Surfers — the premise looks wrong

"There's no gameplay yet" conflicts with the code. `CapySurfersState` contains
the whole loop (`startRun`, `tickJuice`, `submitRefuel`, `commitRefuel`,
`triggerChallenge`, `buildChallenge`, `activatePowerup`, `tickPowerup`, plus
missions), and `CapySurfersGameView.swift:304` threw *"Switch must be
exhaustive"* — you don't get a powerup/world switch without a game loop.

Two likely explanations:

- **(a) Unhosted** — no `SpriteView(scene:)` is ever constructed from the Play tab.
- **(b) Hosted but instantly frozen** — `startRun()`'s `energy == 0` branch sets
  `needsRefuel = true` with `preRunWarmup = false`, so the scene renders as a
  dead screen and reads exactly as "doesn't launch."

**So "Option A: build the minimal loop" is the wrong work** — it means writing a
second minigame. The cheap Option A is **host and verify the existing loop**.
If it's the freeze bug, it's a one-line fix and the game is already done.

Also from the earlier audit, still open:
- `makeMCQ` does `.shuffled().prefix(3)` **before** filtering against `correct`,
  so the ghost `—` option can still appear despite `hasEnoughDistractors`.
- `.shield` never expires (`tickPowerup` guards `p != .shield`).
- `claimReward(state:)` guards on `CapySurfersState.shared` while writing to its
  own parameter.
- 4 of 8 powerups (`headStart`, `doubleCoins`, `timeFreeze`, `brainBoost`) apply
  nothing unless the Scene writes `scoreMultiplier`/`melonMultiplier`/`speedMultiplier`.
- The demo money shot is dead on the demo deck: `demokDeckMCQ` sets
  `itemID: nil`, and `submitRefuel` only writes mastery `if let id = c.itemID`.

---

## 8. Design list

- **Blue "Surf Now" / "Shop":** the `AccentColor.colorset` → `#33CC66` fix is in
  place but is **necessary and not sufficient**. Add `.buttonStyle(.plain)` +
  explicit `.foregroundStyle(...)` at those two call sites, then **Cmd+Shift+K**
  — a stale `Assets.car` is the #1 reason an accent change looks inert.
- **Emoji:** 🔥 → `flame.fill`, 💡 → `lightbulb.fill`, ✨ → `sparkles`.
- **"good e…":** fixed; verify with `lineLimit` + `minimumScaleFactor` at large
  Dynamic Type on a small device.
- **"Copy of":** strip at ingest (title derived from filename), not by renaming
  one deck, or it recurs for anyone who imports a duplicate.

---

## 9. Nothing has compiled

Every build attempt has failed because the shell cannot spawn
(`posix_spawn 'bash'` ENOENT). Everything above is statically reviewed, not
verified. Run this yourself and paste the output back:

```bash
cd /Users/zoey/Desktop/VerbaDoc/VerbaDoc
xcodebuild -project VerbaDoc.xcodeproj -scheme VerbaDoc \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/verbadoc-dd build CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|BUILD' | head -60
```

Also still unverified: `StudyGuideView.swift` may declare `viewAppearTime`
twice, which would block the whole target.

---

## 10. Housekeeping

This file sits at the repo root (`/Users/zoey/Desktop/VerbaDoc/VerbaDoc/`), so
it will show as **untracked** in `git status`. Add `NEXT-STEPS.md` to
`.gitignore` if you don't want the noise in a demo.

Grep target for the one unverified name collision: `grep -rnw 'ErrorKind' --include='*.swift' .`
— `ErrorPresentation` and `VerbaErrorBanner` are specific enough to be safe,
but `ErrorKind` is generic enough that `Features/` could already have one.
