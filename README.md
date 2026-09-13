# Sheep

An offline AppKit menu-bar home for the classic eSheep. Built for Apple Silicon, validated on macOS 26.5.2 using Apple's command-line tools. No full Xcode, third-party dependencies, account, server, catalog, updater, or telemetry.

## Download

For the latest automated build, open [Build Sheep in Actions](https://github.com/two06/Sheep/actions/workflows/build.yml), select a successful `main` run, and download **Sheep-macOS-arm64** from **Artifacts** (GitHub sign-in required). Unzip the artifact, then its `Sheep.zip`, and move Sheep.app to Applications. Artifacts expire after 30 days.

Builds require Apple Silicon (M1 or newer), target macOS 13+, and have been tested on macOS 26.5.2.

The app is ad-hoc signed, not Apple-notarised, so macOS may block its first launch. To allow it to open:

1. Move the extracted **Sheep.app** into **Applications** and try opening it.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about Sheep and click **Open Anyway**.
4. Confirm **Open** in the prompt, authenticating if asked.

macOS saves this exception so you can open the app normally next time. See [Apple's instructions](https://support.apple.com/en-gb/102445). If **Open Anyway** is missing or the alert says the app is **damaged**, report the exact message for troubleshooting.

Controls appear in the menu bar rather than a normal app window.

## Run

The built app is `dist/Sheep.app`. Double-click it, or:

```sh
open dist/Sheep.app
```

Use the 🐑 menu to add/remove sheep, pause/resume, hide/show, choose size, change Launch at Login, or quit. The menu lists the current flock size. **Menu Bar Icon** switches the status item between the emoji and a monochrome glyph derived from the original eSheep icon; the glyph is a template image, so macOS tints it like its own status icons in light and dark menu bars. Drag a sheep by its visible pixels; release while moving to toss it. Right-click a sheep for a menu that adds or removes sheep, plays one of its animations (Walk, Run, Jump, Sleep, Eat, Take a Bath, Boing, Pick a Flower) or a random Surprise Me, and mirrors the pause/resume, hide, and size controls. Paused sheep still accept right-clicks so you can resume them; dragging stays disabled while paused. Temporary flowers, bath effects, and the black-sheep partner don't increase your saved sheep count.

Defaults are one sheep, original 40 × 40 point size, animation enabled, the emoji menu bar icon, and Launch at Login disabled. Count, size and icon style persist; animation states start fresh. You can remove the last sheep for the current session and keep the menu item. Launching or reopening Sheep restores at least one sheep; reopening also shows and resumes a hidden or paused flock. The app limits the chosen count to 100.

For Launch at Login, keep the app at a stable path before enabling it (for example `~/Applications/Sheep.app`). macOS may request approval in Login Items. The menu reflects the actual ServiceManagement registration state. Moving or rebuilding an ad-hoc-signed app may require disabling and re-enabling its login registration.

## Build and test

[`.github/workflows/build.yml`](.github/workflows/build.yml) tests and packages the app on GitHub's `macos-26` Apple Silicon runner for pull requests and pushes to `main`. To build manually, choose **Actions → Build Sheep → Run workflow** after the workflow is on the default branch. It verifies the packaged resources and signature, creates a ZIP with macOS bundle metadata preserved, and uploads it as an artifact. No signing secrets are required; builds remain ad-hoc signed and unnotarised. The workflow does not publish releases or commit generated binaries.

```sh
swift build
scripts/test.sh
scripts/package.sh release
open dist/Sheep.app
```

`package.sh` creates an arm64 app with stable bundle identifier `local.james.Sheep`, embeds the original definition/artwork and credits, renders the app icon from the definition's embedded eSheep icon with `scripts/make-icon.swift` and `iconutil`, and ad-hoc signs and verifies the bundle. It stages the replacement so rebuilding does not overwrite the executable of a running instance. It uses `swift`, `codesign`, and standard macOS command-line tools. Dependencies and resources are local after checkout. Build output goes under `.build/` and `dist/`.

`test.sh` supplies Swift Testing's framework and runtime paths for the standalone command-line-tools installation; neither XCTest nor full Xcode is needed. Tests cover every bundled animation/frame/transition reference, expression conversion and repeat semantics, weighted conditions, interpolation, flipping, effect cleanup, transparent sprites, window occlusion, swept landings, moving/vanishing support, monitor geometry, and deterministic long runs. Swift's build caches must be writable.

To check resources in the packaged app without launching its UI:

```sh
dist/Sheep.app/Contents/MacOS/Sheep --self-check
```

To build the development animation selector:

```sh
scripts/package.sh debug
open dist/Sheep.app
```

The debug menu's **Inspect Animation** submenu selects any of the 54 original sequences on the first sheep. It moves that sheep to the usable bottom centre, clears existing effects, and resumes animation. Normal transitions and collision rules remain active. A release build omits the selector.

## Architecture

- `SheepCore`: XML definition and arithmetic reader, deterministic per-sheep randomness, animation graph, spawning/effects, collisions, support tracking, and toss physics. Accepts elapsed seconds, environment snapshots, and interaction events; exposes render states and spawn/removal events.
- `SheepMac`: cached sprites and alpha masks, nonactivating transparent `NSPanel` windows, input, AppKit/Core Graphics coordinate conversion at the boundary, visible-window enumeration, display snapshots, the menu bar template glyph and preference persistence, and resident-memory instrumentation.
- `Sheep`: status menu, preferences, ServiceManagement, lifecycle notifications, independent 60 Hz simulation/input and 10 Hz shared geometry timers.

The simulation uses global logical desktop points, X rightward and Y downward, with the origin at the primary display's top-left. Monitor origins may be negative. Retina scale is handled by AppKit; sprite size is specified in logical points and rendered with nearest-neighbour interpolation.

Window tops are clipped to displays and portions covered by higher ordinary windows are subtracted. Feet use a swept point test at their centre. Support is tracked by window ID so sheep travel with a moved window and fall when support disappears or becomes covered. Adjacent usable displays permit crossing; separated displays have boundaries. Display removal relocates stranded sheep. The usable bottom edge follows the Dock. Window tops without enough room below the menu bar for the current sheep size are skipped.

Authored movement is per animation frame. Movement uses `step / (totalSteps - 1)`; visual timing, opacity, and vertical offsets use `step / totalSteps`, following the upstream engine. Repeat counts truncate toward zero, while `Convert(...,System.Int32)` uses nearest-even rounding. `repeatfrom` identifies the start of the repeating tail. Missing next transitions respawn sheep and remove child effects. Children inherit their parent's facing and spawn random value, then own independent state. A 128-effect guard and a 10-minute maximum effect lifetime protect against runaway state; bundled effects terminate naturally much sooner.

Tosses use release velocity, short physics substeps and swept collisions. After a short airborne toss, the sheep returns to the authored falling sequence; landings select the original soft/hard landing animations. Platform sleep/session notifications and explicit Pause/Hide invalidate simulation and geometry timers. While paused, mouse hit testing continues so the sprite context menu remains available. Resume rebuilds geometry before advancing time. Sheep animation is frozen on displays covered by full-screen windows.

## Desktop behaviour and limits

Window bounds are obtained from `CGWindowListCopyWindowInfo` metadata. Sheep never requests Screen Recording or Accessibility permission and never captures other apps' pixels, text, or window titles. The initial prototype detected five ordinary windows with usable bounds while Screen Recording permission was off.

Panels join ordinary Spaces, are transient in Mission Control, and cannot become key/main windows or full-screen tiles. Public window metadata does not expose a reliable full-screen Space identifier. The app therefore also hides sheep on displays with an ordinary window covering the entire display bounds; this intentionally includes borderless full-screen video. A full-screen transition can take up to one geometry refresh (nominally 100 ms) to be recognised. This is a conservative geometry rule, not a private Space API. Stage Manager, Mission Control, split-screen and unusual window managers still need visual checks on the intended desktop setup.

Mouse acceptance follows the current sprite alpha mask and cursor position at 60 Hz, and stays enabled during dragging. Extremely rapid move-and-click gestures between samples remain a timing limit of this permission-free approach. Effects always pass clicks through. Screen-lock distributed notifications supplement public workspace session and screen-sleep notifications.

Compatibility is limited to the pinned classic `esheep64` definition. There is no arbitrary pet import or editor. The source assets and usage context are recorded in [Vendor/NOTICE.md](Vendor/NOTICE.md).

## Validation

See [docs/VALIDATION.md](docs/VALIDATION.md) for observed results and the remaining manual matrix.

A reproducible live soak is available after packaging:

```sh
scripts/soak.sh
```

It starts separate one- and ten-sheep instances (11 sheep total) without modifying saved count/size, logs every five seconds under `.build/validation/`, and quits them after about 31 minutes. Each pauses from roughly 10–20 seconds, hides from 20–30 seconds, then runs for at least another 30 minutes. Logs include resident memory, visible/total panels, effects, simulation ticks, geometry polls, polling cost, and rendered-versus-simulated position error. Run `scripts/analyze-soak.py <one-sheep-log> <ten-sheep-log>` to validate them. Keep the Mac awake and on an ordinary desktop during the run. This live check is distinct from the accelerated deterministic simulation tests.
