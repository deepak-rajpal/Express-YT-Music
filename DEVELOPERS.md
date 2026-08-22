# Developer guide

Everything technical about Express YT Music. If you only want to *use* the app, the
[README](README.md) is the friendlier door.

- [The short version](#the-short-version)
- [How it stays under 1 MB](#how-it-stays-under-1-mb)
- [Tech stack](#tech-stack)
- [Folder layout](#folder-layout)
- [How it works](#how-it-works)
- [Building and testing](#building-and-testing)
- [Design decisions](#design-decisions)
- [Things that will bite you](#things-that-will-bite-you)

## The short version

A menu-bar-only macOS app. One `WKWebView` runs the real `music.youtube.com`, and a small
JavaScript file injected into that page reports what's playing and exposes playback controls.
Native Swift wraps it in a menu-bar item, a drop-down window, a floating mini player, global
hot keys and macOS Now Playing integration.

No Xcode project, no package manager, no dependencies. Just Swift files and a `Makefile`.

```bash
git clone <this repo> && cd express-yt-music
make install     # builds and copies to /Applications
make test        # three offline test suites
```

Command Line Tools are enough (`xcode-select --install`); full Xcode is not required.

## How it stays under 1 MB

Here is the entire shipped app:

| File | Size | What it is |
| --- | --- | --- |
| `Contents/MacOS/ExpressYTMusic` | 677 KB | All the Swift, compiled — both architectures |
| `Contents/Resources/AppIcon.icns` | 325 KB | The icon, at ten sizes |
| `Contents/Resources/inject.js` | 6 KB | The page bridge, shipped as plain text |
| `Contents/Info.plist` + `PkgInfo` + signature | ~4 KB | |
| **Total** | **~1012 KB** | universal; an arm64-only build is ~690 KB |

The `.dmg` compresses that to about 745 KB. Note the universal bundle sits just under the 1 MB
line, so the README says "under 1 MB" rather than a figure that would rot on the next change.

One decision does most of the work: **we ship zero libraries and link 31 from macOS.**

```
libraries bundled inside the app : 0
system libraries linked at runtime : 31
```

Every Mac already has WebKit, AppKit and the media frameworks. Electron apps instead bundle their
own copy of Chromium and Node in every app, which is why they start around 200 MB. Swift also
compiles to native code, so there is no interpreter or runtime to carry.

A third of this repository is tests and build tooling that never ships.

## Tech stack

| Concern | What's used |
| --- | --- |
| Language | Swift 5 (builds with Swift 6 toolchains in Swift 5 language mode) |
| UI | AppKit — `NSStatusItem`, `NSPanel`, Auto Layout, all programmatic, no storyboards |
| Web | WebKit — `WKWebView`, `WKUserScript`, `WKScriptMessageHandler` |
| Media integration | MediaPlayer — `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| Global hot keys | Carbon — `RegisterEventHotKey` |
| Launch at login | ServiceManagement — `SMAppService` |
| In-page logic | Plain ES5-flavoured JavaScript, no build step |
| Build | `make` + `swiftc` |
| Minimum target | macOS 13.0 |

## Folder layout

```
express-yt-music/
├── Makefile                  every command lives here
├── README.md                 user-facing
├── DEVELOPERS.md             this file
├── Sources/                  Swift — compiled into one binary
├── Resources/                copied into the .app as-is
├── Tools/                    build helpers and tests, never shipped
├── Tests/                    test fixture
├── docs/screenshots/         README images
├── download/                 the released .dmg
├── build/                    generated (gitignored)
└── dist/                     generated (gitignored)
```

### `Sources/`

| File | Lines | Responsibility |
| --- | --- | --- |
| `main.swift` | 8 | Entry point; sets `.accessory` activation policy |
| `AppDelegate.swift` | 70 | Wires the pieces together at launch |
| `WebPlayerController.swift` | 320 | **Core.** Owns the web view, injects the bridge, navigation policy, popups, sign-out |
| `FirstPartyHosts.swift` | 27 | Regex deciding whether a host is Google/YouTube |
| `PlayerState.swift` | 67 | `PlayerState` struct + `PlayerStore`, the single source of truth |
| `Preferences.swift` | 101 | `UserDefaults` wrapper and launch-at-login |
| `StatusBarController.swift` | 282 | Menu-bar item, the separate Next item, the menu |
| `PopupController.swift` | 165 | The drop-down `NSPanel` hosting the web view |
| `MiniPlayerController.swift` | 337 | The borderless floating mini player |
| `MiniPlayerLayout.swift` | 49 | Mini-player geometry and fonts, shared with the layout test |
| `ShortcutSettingsController.swift` | 197 | The hot-key recording window |
| `NowPlayingBridge.swift` | 158 | Control Centre, lock screen, media keys |
| `HotKeyManager.swift` | 208 | Carbon hot-key registration |
| `Diagnostics.swift` | 48 | Appends to `~/Library/Logs/ExpressYTMusic.log` |

### `Resources/`

| File | Responsibility |
| --- | --- |
| `inject.js` | Runs inside the YouTube Music page: reports state, exposes `window.__eym` controls |
| `Info.plist` | `LSUIElement` (no Dock icon), bundle id, version, icon name |

### `Tools/` and `Tests/`

| File | Responsibility |
| --- | --- |
| `makeicon.swift` | Draws `AppIcon.icns` at build time, so no binary image assets live in the repo |
| `hosttest.swift` | 38 cases over `FirstPartyHosts`, including look-alike domains |
| `layouttest.swift` | Asserts the mini player cannot stretch, clip, or shrink its text column |
| `bridgetest.swift` | Runs `inject.js` against `Tests/fixture.html` in a real `WKWebView`, offline |
| `probe.swift` | Loads Google's sign-in page and prints what it serves — a canary |
| `Tests/fixture.html` | A stand-in YouTube Music page: `<video>`, `mediaSession` metadata, player-bar DOM |

## How it works

```
   ┌───────── music.youtube.com, inside a WKWebView ─────────┐
   │  Resources/inject.js runs here at document-end          │
   └──────┬───────────────────────────────────▲──────────────┘
          │ state: title, artist, artwork,    │ commands:
          │ isPlaying, elapsed, duration      │ window.__eym.next() etc.
          │ (postMessage → bridge)            │ (evaluateJavaScript)
          ▼                                   │
   ┌──────────────────────────────────────────┴────┐
   │  WebPlayerController                          │
   └──────┬────────────────────────────────────────┘
          ▼
   ┌───────────────┐
   │  PlayerStore  │  single source of truth, posts .playerStateChanged
   └───┬────┬──────┴──┐
       ▼    ▼         ▼
  StatusBar Mini    NowPlayingBridge
    item   player   (Control Centre, media keys)

  HotKeyManager ──────► WebPlayerController (⌃⌥⌘ combos)
```

**Reading state.** `inject.js` polls every 500 ms and also listens to `play`, `pause`, `seeked`
and friends on the `<video>` element. It only posts when something meaningful changed, so the
bridge isn't chatty. Metadata comes from `navigator.mediaSession.metadata` — a public API that
YouTube Music populates itself for OS integration — and falls back to scraping the
`ytmusic-player-bar` DOM only if that is empty.

**Sending commands.** Swift calls `evaluateJavaScript("window.__eym.next()")`. Track skipping
prefers the page's own `#movie_player.nextVideo()` and falls back to clicking the transport
buttons.

**Why not an `<iframe>`?** Two reasons. YouTube Music sends `x-frame-options: SAMEORIGIN`, so a
frame simply refuses to render. And even if it loaded, the same-origin policy would stop our
JavaScript reading anything inside it. A `WKWebView` makes *us* the browser, so we can inject a
user script — the same mechanism a browser extension uses.

**Adding UI.** Subscribe to `.playerStateChanged` and read `PlayerStore.shared.state`. Never read
the web view directly; that's the rule that keeps the status bar, mini player and Now Playing
centre from drifting out of sync.

## Building and testing

| Command | Does |
| --- | --- |
| `make` | Build for this Mac (arm64) into `build/` |
| `make universal` | Fat arm64 + x86_64 binary |
| `make run` | Build and launch |
| `make install` | Build and copy to `/Applications` (kills the running copy first) |
| `make dmg` | Package a disk image |
| `make test` | The three offline suites |
| `make check` | Type-check only, no binary |
| `make probe` | Hit Google's sign-in page and print what it serves |
| `make clean` | Remove `build/` |

`make test` runs, in order:

1. **host matcher** — 38 cases, including rejections for `google.com.example.net` and
   `youtube.com.attacker.io`. This gates what may load in a window holding a live session, so it
   is deliberately paranoid.
2. **mini-player layout** — builds the real constraint graph with the real fonts and asserts the
   window cannot be stretched by a long track name, that the text column stays legible, and that
   the rows fit the window height.
3. **page bridge** — loads `Tests/fixture.html` in a `WKWebView` with the real `inject.js` and
   asserts on 20 behaviours: `mediaSession` parsing, largest-artwork selection, `<video>` state,
   play/pause, seek, next/previous via the player API, shuffle/repeat, the double-injection guard,
   and the DOM fallback path.

All three are offline. `make probe` is the only thing that touches the network, and it exists
because the sign-in flow is the one part that can break from the outside.

### Signing

`make` applies an **ad-hoc signature** (`codesign --sign -`). That is enough for local use and
keeps the bundle identity stable so macOS remembers permissions between rebuilds. To distribute
without the Gatekeeper warning you need a paid Apple Developer account:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" "build/Express YT Music.app"
xcrun notarytool submit ... && xcrun stapler staple ...
```

Change `CFBundleIdentifier` in `Resources/Info.plist` to your own reverse-DNS first.

## Design decisions

Some choices are deliberate and worth explaining before you "fix" them.

**A truthful user agent.** `WKWebView`'s default UA omits the `Version/x Safari/x` token, so sites
treat it as an unknown browser. We add just that token via `applicationNameForUserAgent`, giving a
UA that is genuinely accurate — this really is Safari's engine. We do **not** claim to be Chrome,
and we do not touch `navigator.webdriver`, `navigator.plugins` or `navigator.userAgentData`.
Google serves a normal sign-in form to an honest Safari UA; `make probe` verifies that still holds.

**Sign-in stays in the app.** Cookies live in this app's own persistent `WKWebsiteDataStore`.
Nothing reads another browser's profile, cookie jar, or saved logins. "Sign Out" calls
`removeData(ofTypes:)` on our store only.

**Carbon hot keys, not a global event monitor.** `NSEvent.addGlobalMonitorForEvents` is the usual
way to do global shortcuts, but for key events it requires Accessibility permission and then
delivers *every* keystroke in *every* app to your process. `RegisterEventHotKey` needs no
permission and only ever delivers the exact combinations you registered. Shortcut *recording* uses
a local monitor, active only while that window has focus.

**Navigation policy.** Only a deliberate `linkActivated` navigation in the main frame, to a host
outside Google's and YouTube's domains, is handed to the default browser. Redirects, form
submissions and script-driven navigation always stay in the app — sign-in and the channel picker
bounce through many hosts, and diverting any one of them mid-flow breaks the flow.

**`window.open()` gets a real child window** built from the configuration WebKit hands over, so it
shares the cookie store. Google's account and channel pickers use popups; loading their URL into
the main web view instead replaces the player with a blank page.

**The player self-heals.** Every time the window is shown, `loadHomeIfNeeded()` checks whether the
web view is on a blank or stranded page and reloads. Cheap insurance against a flow that leaves it
somewhere useless.

**`mediaSession` before DOM scraping.** Class names like `.title.ytmusic-player-bar` are Google's
internals and rot without warning. `navigator.mediaSession.metadata` is a public, documented API
that YouTube Music fills in itself. Scraping is the fallback, and `make test` covers both paths.

**No telemetry.** The app makes no network requests of its own. The only host in the compiled
binary is `https://music.youtube.com/`, and you can check that yourself:

```bash
strings -a "/Applications/Express YT Music.app/Contents/MacOS/ExpressYTMusic" \
  | grep -Eio 'https?://[a-z0-9./_?=&%:@~#+-]+' | sort -u
```

## Things that will bite you

**AppKit views are bottom-left origin.** Constraints that look right can put things off-screen.
`layouttest.swift` measures from the top deliberately.

**Constraints govern the alignment rect, not the frame.** An `NSTextField`'s frame is a couple of
points wider than the rect Auto Layout positioned, which will make exact-width assertions fail
until you use `alignmentRect(forFrame:)`.

**Do not put labels in an `NSStackView` pinned on both sides.** A stack sizes itself in the cross
axis to its widest subview's intrinsic width. With a long artist name that demanded over 400 pt
inside a 236 pt window, and AppKit widened the *window* to satisfy it. The fix is a required width
constraint on the content view plus lowered compression resistance on the labels, so they lose and
truncate. `layouttest.swift` guards this specific regression.

**`minSize`/`maxSize` do not stop a programmatic resize.** They constrain the user dragging edges.
`setContentSize` sails straight through.

**A long `NSWindow.title` does not widen a panel** — I assumed it did and was wrong. Worth knowing
if you go hunting for a sizing bug.

**Menu-bar item order is creation order, right to left.** The most recently created item sits
furthest left. Set `autosaveName` so a user's ⌘-drag rearrangement persists.

**`tertiaryLabelColor` vanishes inside an `NSVisualEffectView`.** Vibrancy makes it nearly
transparent. Use `secondaryLabelColor` for anything that must stay visible on a blurred backdrop.

**`NSImage.lockFocus()` renders at the main display's backing scale, not at the image's size.**
On a Retina Mac an `NSImage(size: 1024)` therefore produces a 2048×2048 bitmap — four times the
pixels, and an `.icns` a third larger than it needs to be. If you need exact pixel dimensions,
draw into an `NSBitmapImageRep` whose `size` equals its pixel count, as
[`Tools/makeicon.swift`](Tools/makeicon.swift) does.

**Multi-file `swiftc` builds forbid top-level code.** Only `main.swift` may have statements at file
scope, which is why some tools in `Tools/` use `@main` and others don't — the single-file ones are
compiled alone.
