# LightCraft: user-story UX validation, iPadOS and iOS

Reuse current story/tour ownership: Light orchestrator owns F and tour fixes. Latest parent/Luna evidence: A/C/D/E/H/I passed, F passed with a created Subject mask and exposure 0→1, and the moved-original Swift regression passed. The portrait tour remains incomplete: the latest run reached Edit, Profiles and Crop, then Remove's native Find menu blocked seven later tabs. An anchored Remove popover now builds but awaits simulator validation. Guided Upright overlay, model-dependent blemish finder, Smart Album/Print/Contact Sheet are documented limitations. Confirm current implementation before declaring any old limitation fixed.

## Story-to-test matrix

| User goal | iPadOS executable case | iOS executable case / gap | Required observable result |
|---|---|---|---|
| Cull a Photos library and develop an image | `UserStoryUITests/testStoryACull`, `testStoryBDevelopBasics`, `testStoryCCrop` | Same selectors, portrait; use sheet controls, never require dock | Rating/flag, develop value and crop change; undo restores original |
| Save back without losing the original | `DevicePhotosUITests/testEditWritesBackRestoresAndReverts`, `testSaveCopyToPhotos` | Same selectors with real seeded Photos asset | PhotoKit adjustment restoration and revert; demo alone cannot prove write-back |
| Local mask and reusable settings | `UserStoryUITests/testStoryECopyPasteSettings`, `testStoryFMasking`, `testStoryHHistoryAndVersions` | Same stories, actual phone sheet route | Mask row exists; pasted target marked edited; version restore |
| Fast input and appearance | `UserStoryUITests/testStoryIKeyboardShortcuts`, `testStoryJMultiFingerUndoRedo`, `testStoryKDarkAndLight` | Same, external keyboard route where supported | Actual action outcome, no success from a missing control |
| Every panel and full screen | `PanelTourUITests/testPanelsPortrait`, `testPanelsLandscape`; `LightCraftUITests/testFullScreenCanvas` | Portrait panel tour + fullscreen | Open and act on each panel; selected tab/phone sheet reachable; exit restores editor |

## Execution and evidence rules

Astra authored/reviewed these cases on 2026-10-24; Luna executes. New cases are **not yet runtime validated**. Sol owns production fixes and generic `build-for-testing`; regenerate XcodeGen to include new files. Use current `apple/build/dd`, never an old `dd-core` bundle.

1. Shared iPad `81A653B3-9027-4C16-8335-320CB937C66C` first: portrait, then landscape, then genuinely resized narrow window if available. Shared iPhone `FF7E37C5-12E6-483D-8887-D09D18EEB4A4` only after iPad fixes. One simulator under workspace `.sim.lock`; no build while holding it.
2. Run `-only-testing:LightCraftUITests/<Class>/<method>` with the names above, `-collect-test-diagnostics never`. No screenshots. Retain assertion text, hierarchy/frames, logs and notes. Remove app/runner after each run per cookbook.
3. Record build path/commit, device, window size, orientation, appearance, fixture/permission state, exact selector, completed/failed/aborted, first failing step and full error. A skipped case, early return, missing fixture or NOT-REACHED is **not** a passed workflow.
4. Photos integration needs a known seeded asset and explicit granted/denied/limited states. Native-copy tests need known source bytes/hash, produced native URL and repeat-open identity. Demo data proves editing UI only. Never touch a personal library fixture.
5. Compare tap count only for the same route and setup. Review clipped/hittable frames, selection traits, return-to-canvas, sheet dismissal and contextual actions. System menu rows under 44pt alone are not UX bugs. Menu plus hardware shortcut is legitimate duplication; the user rejected parallel floating panel launchers.

## Remaining cross-platform acceptance work

- Reorder/stack and collapsed/selected panel state across app termination **without reset launch arguments**; PhotoCraft already has a reusable persistence case. Repeat Window/menu route separately from dock Add; selected tab must scroll into view when already selected, collapsed or previously hidden.
- Real narrow-window resizing (Stage Manager/Split View), landscape transitions mid-edit, dark/light and large Dynamic Type. Orientation alone is not proof of resizable-window support. Accessibility evidence cannot establish contrast/color correctness without render inspection; no screenshots requested.
- Hardware shortcuts and multi-finger undo/redo must show document changes, not just menu presence. Pencil hover/squeeze/pressure and physical keyboard behavior need an appropriate device pass; list unavailable hardware as unverified, not successful.
- Native document/library persistence and import/export roundtrip beyond available tests, error recovery, permission denial and media relinking. Unsupported features remain tracked gaps.

## Bounded UX review findings

| Priority | Platform | Evidence / reproduction | Interpretation and next action |
|---|---|---|---|
| P1 | iPad / all platforms at risk | Vector shortcut duplicate caused launch crash; earlier runtime used stale dd-core | Root reports source fix + regression; Luna must run current bundle before UX suite |
| P1 | Light iPad | Masking Add → Subject did not create mask; later Crop/Remove failed after cached original absolute path became stale | Root reports repairs; rerun F and tour on fresh current bundle; no cascade counted as separate proven defect |
| P2 | Film iPad | Portrait 834pt tried to find wide dock (`>=900`) | Test setup defect fixed with landscape case and separate portrait sheet story |
| P2 | Fig iPad | New Design duplicate query failed to open document | Test fixture fixed via hittable candidate plus strict demoReady/canvas; await current run |
| P2 | iOS and iPadOS | Legacy smoke steps often log missing action as notes; iPad-only panel tests skip/return on phone | New strict result stories reduce false green; inspect legacy notes and keep remaining phone gaps explicit |

This report incorporates parent/Luna observations, not an independent runtime pass. Each new failure must be classified as product defect, test defect or unavailable fixture before a production change.

## Focused execution handoff

After the app owner rebuilds the complete test bundle and Luna obtains the shared lock, run from `lightcraft-ios/lightcraft-ios/apple` (choose a fresh result path):

```sh
xcodebuild test-without-building -scheme LightCraft -derivedDataPath build/dd \
  -destination 'id=81A653B3-9027-4C16-8335-320CB937C66C' \
  -only-testing:LightCraftUITests/UserStoryUITests/testStoryFMasking \
  -collect-test-diagnostics never -resultBundlePath build/results/story-ipad.xcresult
```

Substitute other exact selectors from the matrix. After iPad fixes pass, repeat applicable cases with destination `id=FF7E37C5-12E6-483D-8887-D09D18EEB4A4` and a distinct result bundle. Use the existing orchestrator lock/uninstall wrapper; this command alone does not acquire the workspace lock. Require the requested test name and a nonzero completed-test count in results: exit zero with zero executed tests is not a pass.

## Phase 2 evidence review (2026-10-24)

- **Film iPad:** read `filmcraft-ios/apple/build/results/luna-story-suite.log`; three requested cases executed and failed. Landscape width precondition passed, but dock `menu.panels` existed and was not hittable. Portrait `menu.more` was absent. Split added a clip (strict assertion passed), then `command.edit.undo` was absent: cut is observed, undo/redo remains unreached. Portrait hierarchy in `/tmp/film-story-attachments/D9415F75-5DA6-4D1D-92CD-75EF5E5C0557.txt` has editing/transport controls but no navigation bar/Undo. Source DemoApp → DemoWindow → EditorScene has no NavigationStack while PadEditorView supplies Undo/More only through toolbar. **P1 fixture-host hypothesis:** demo may omit toolbar navigation host; sent to Film owner. Do not infer an undo-engine defect or generalize to normal DocumentGroup. Landscape dock hit testing needs separate frame evidence.
- **Fig iPad:** read `figcraft-ios/apple/build/results/luna-dock-final.log`: one case executed, failed before demo at dynamic button enumeration with stale element index 10. This is a setup failure; no dock assertions reached. Fig owner owns a stable exact-label New Design retry helper and replacement in both dock and new opacity story. No independent all-buttons opener should be reintroduced.
- **Vector:** latest Luna report confirms six catalog consistency tests passed, including reserved paste shortcut regression. Dock run executed zero tests because test binary lacked that selector. Require regenerated project/current test binary, nonzero count and named selector; a green process exit is not runtime UX proof.
- **Photo:** new phone stories are source-authored only, not compiled/executed. The no-screenshot reusable cases are EditCopy, NewFromPhoto, PlacePhoto, Fullscreen and UserStory S1–S9. Do **not** schedule legacy PhotoCraftUITests/testScreenshotsDark or testScreenshotsLight: their `shot` helper calls XCUIScreen.main.screenshot(), contrary to this run's request.
- **Light:** iPad F passed with a real mask and exact exposure change; the moved-original regression and Crop pixel commands passed. The latest portrait tour reached 3/11 before Remove's native Find menu blocked navigation; the anchored replacement has a green generic build pending a simulator rerun. Neither the remaining seven dock panels nor iPhone are validated.

## Remove-panel decision after current iPad tour (Astra, 2026-10-24)

Reviewed the actual tour summary `apple/build/results/ipad-LightCraftUITests-PanelTourUITests-testPanelsPortrait/8B2E0665-CCD9-42C1-AB63-0AB9C872FE05.txt` and hierarchy `876FCEB6-6986-4ACF-93F6-9914CB1AD824.txt`. Four panels were recorded reached, seven later not reached. The recorded Remove action `tap command.spot.findBlemishes` was **not execution evidence**: hierarchy explicitly marks that menu item Disabled, with Find still open. Later tab misses are blocked-navigation fallout, not seven proven absent panels.

Minimal repair owned by Light Sol: reject disabled actions before tapping/counting; dismiss the native Find menu and verify it no longer blocks navigation. Exercise available Find Dust; record Find Blemishes separately as `UNAVAILABLE: face model not installed / capability not tested`, preserving the engine reason. Never label disabled capability passed. Panel opening/action coverage can succeed independently of incomplete Remove feature coverage.

User-intent gap (P2, both platforms by shared source): RemovePanel directs users to place spots with a Remove tool, but Core/Tool.swift and LoupeView expose no manual Remove canvas tool/overlay. Do not replace automatic detection with an invented gesture test. The engine has spot.add and a catalog parameter path may be usable, but that is not a verified touch-retouch workflow. Keep manual spot placement incomplete; no model download or new production feature is authorized by this bounded test repair.

Find Dust legitimately returns zero candidates on a clean image (`spot.findDust` implementation). Enabled dispatch + no error proves accessible detection action, not successful spot creation/removal. A future retouch-outcome test needs a known dust fixture, visible spot row added, selection/delete and undo restoration; until then report detection action coverage and retouch outcome separately. If an explicit automatic-blemish story is later scheduled, missing models must make that story unavailable/blocked, never pass; other panels must still run.

Luna reports current source-relocation units 4/4 and Story F pass (mask created, exposure 0→1); Crop and Find Dust no longer produce stale-original errors. These improve evidence but do not close the full panel tour or iPhone validation.
