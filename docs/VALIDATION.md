# Validation record

Environment: Apple Silicon, macOS 26.5.2 (25F84), Apple Swift 6.3.2, command-line tools, 2026-09-11. One physical display was present during the initial prototype.

## Observed

- Prototype built and ran as a transparent nonactivating panel using the original sprite.
- Prototype report: 176 frames, 40 × 40 logical points; `canBecomeKey == false`, `canBecomeMain == false`.
- `CGWindowListCopyWindowInfo` returned five ordinary windows and bounds for all five with Screen Recording permission off. No permission request API is used.
- User confirmed the prototype moved/dragged. The user initially reported its disappearance before finishing the checks; its process was still running when inspected, and no Sheep crash report was found. The user subsequently reported “tests look good.” Individual Space/Stage Manager scenarios were not separately recorded.
- 20 Swift Testing tests passed, including deterministic accelerated 30-minute simulations with one and ten sheep, in 3.035 seconds on this Mac. This is a simulation-duration test, not a claim of 30 minutes of desktop runtime.
- Packaged debug app passed resource self-check, Info.plist validation, and strict ad-hoc signature verification, and launched successfully through LaunchServices.
- Initial live one-sheep polling averaged about 2.5 ms; no runtime errors appeared in its metrics log.
- User explicitly confirmed full-screen exclusion and ordinary desktop switching work.
- User reported sheep appearing to walk unsupported. Reproduced an AppKit constraint mismatch: requested global panel Y = −6 became actual Y = 33. Overriding `constrainFrameRect` fixed it; the live check now reports requested/actual Y values equal at −150, −6, 33 and 100. A dedicated AppKit regression test covers the failure. The user subsequently explicitly confirmed that window alignment is fixed. Near-menu-bar ledges without room for the sheep are also skipped.
- A live ordinary-window fixture verified falling onto window ID 13578 (at 1.71 seconds), carrying the sheep when the window moved +100 X / −60 simulation Y (12.51 seconds), starting an authored fall when it closed (23.21 seconds), and landing at the Dock boundary (26.71 seconds). Geometry and animation IDs were recorded locally in `/tmp/sheep-fixture-metrics.jsonl`.
- An adjacent-display regression found and fixed a false border at a shared floor seam. Contiguous travel, gap rejection, and crossing into a neighbouring display with a lower Dock boundary now pass.
- A decoded atlas contact sheet was visually inspected: correct orientation and transparent backgrounds. Regenerate it with `swift run SheepProbe --export-atlas` (writes `/tmp/sheep-atlas.png`).
- The first live soak was stopped when the user reported the panel-position bug. It is not a completed acceptance run. The corrected release soak completed successfully; see the results below.

## Manual acceptance matrix

Record pass/fail and any reproduction steps on the final app. General positive prototype feedback does not replace the following detailed checks.

| Check | Procedure | Recorded status |
|---|---|---|
| Drag and toss | Drag slowly; release quickly in several directions; land on a window and Dock boundary | Dragging confirmed; live window fixture landing and support loss passed; toss automated in core |
| Sprite context menu | Right-click a sheep: play each Animations entry and Surprise Me; use Add/Remove, Pause/Resume, Hide, Size; confirm actions affect the clicked sheep | Curated animation ids automated against the definition; live desktop result not recorded |
| Transparent input | Click corners and holes over another app; click visible pixels; repeat after flip/resize | Alpha masks automated; individual desktop result not recorded |
| Keyboard focus | Type continuously in an editor while sheep move; drag sheep then continue typing | Non-key/main properties verified; individual typing result not recorded |
| Window support | Land on overlapping windows, move/resize/minimise/close support, bring another window over it | Core geometry automated; live fixture landing/move/close passed; panel-position mismatch reproduced, fixed, and confirmed by user |
| Dock | Change Dock position and size; toggle auto-hide | Usable-frame handling implemented; manual result not recorded |
| Ordinary Spaces | Switch desktops repeatedly with sheep supported and airborne | User confirmed desktop switching works |
| Full-screen | Enter/exit native full-screen and split view; try borderless video; ensure sheep hide and return | User confirmed full-screen works; split view/video not separately recorded |
| Mission Control | Enter/exit while moving a window between Spaces | Transient collection behaviour configured; manual result not recorded |
| Stage Manager | Enable, switch application groups, disable | Manual result not recorded |
| Multiple displays | Move between adjacent displays with different scale; test a gap; disconnect supporting display | Synthetic geometry automated; only one physical display available |
| Sleep / lock | Sleep/wake, lock/unlock, fast user switch; ensure geometry rebuild before movement | Lifecycle handlers implemented; manual result not recorded |
| Pause / hide | Confirm ticks and polls stop, mouse acceptance disables, then resume correctly | Core pause automated; live soak checks app timers |
| Relaunch | Change count and size; quit and reopen | Persistence implemented; final manual result not recorded |
| Login item | Enable from a stable app path, log out/in, disable and repeat | ServiceManagement implemented; actual login cycle not performed |
| Animation fidelity | Debug menu: inspect all 54 sequences, including bath, flower, black sheep, climbs and falls | All sequences loaded/executed in core tests; visual repertoire review not complete |

Full-screen exclusion is inferred from ordinary-window coverage because public CG window metadata has no full-screen Space flag. Do not label that behaviour universally verified solely from a successful build or the collection flags. The desktop-integration gate remains provisional wherever the matrix lacks an observed result.

## Completed live soak

Both runs completed 1,835 seconds, including 1,805 seconds after the initial pause/hide checks. All automated log criteria passed. Raw logs remain under `.build/validation/soak-20260911-101722-{1,10}.jsonl`; the analyser output is retained in [SOAK-RESULTS.txt](SOAK-RESULTS.txt).

| Metric | One sheep | Ten sheep |
|---|---:|---:|
| Steady resident memory | ~112.8 MiB | ~115.3 MiB |
| Median memory growth, early vs final five minutes | 0.063 MiB | 0.016 MiB |
| Peak resident memory, including startup | 114.8 MiB | 117.2 MiB |
| Simulation updates / second after resume | 60.00 | 59.98 |
| Geometry polls / second after resume | 10.00 | 10.00 |
| Mean geometry-poll cost | 4.34 ms | 5.84 ms |
| Peak simultaneous effects | 0 | 1 |
| Runtime errors | 0 | 0 |

Panel counts matched live entities throughout. Rendered coordinates stayed within one physical Retina pixel (0.5 point) of simulation coordinates. Pause and Hide stopped both simulation and geometry counters; Hide removed visible panels. Counts remained stable and both runs stayed visible and unpaused after the scripted resume. The two processes quit automatically.

The final release also includes the separately tested adjacent-display/lower-Dock-boundary fix. That branch is inactive on this one-physical-display machine. The packaging replacement was verified during the soak without interrupting either running process. The release links only macOS system libraries; its embedded resources and ad-hoc signature were verified, including from a relocated bundle.

User-confirmed desktop results: dragging, ordinary desktop switching, full-screen exclusion, and the corrected window alignment. Physical multi-monitor operation, Stage Manager, an actual login cycle, and sleep/lock cycles remain manual checks; they are not claimed as completed by the soak.

## Manual-launch fix

The reported empty manual launch was reproduced with `local.james.Sheep` containing `sheepCount = 0` while the app process was running. Launch now restores at least one sheep, while allowing an empty flock within the current session. Finder-style reopening also shows/resumes the app and replenishes an empty flock. A persisted-settings regression test brings the suite to 21 passing tests. The rebuilt, signed release was launched against the existing zero setting: its live log reported one sheep, one visible panel, no error, and the saved count became one.
