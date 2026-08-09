# DocBot — TODO

_Last updated: 2026-08-09. This file is a handover backlog, not a promise that every lower-priority idea must be implemented. Re-check repository/PR state before acting._

## Priority legend

- **P0** — blocks the current 2.2 release path or risks a broken build.
- **P1** — should be completed before/around 2.2 release or immediately afterwards.
- **P2** — valuable engineering improvement; not a reason to destabilize the current release.

---

## P0 — Full 2.2 RC2 acceptance test

At minimum, validate the following on the managed Windows environment and, where required, on the internal hospital network.

### Startup / storage

- [ ] Stable/test/dev profile selection is correct for the RC version (`DocBot-test`).
- [ ] Existing profile data is not overwritten by bootstrap copying.
- [ ] `attrib -U +P` failure does not block startup.
- [ ] Missing/temporarily unavailable telemetry storage does not block core app functionality.
- [ ] Existing telemetry InstallationId is used without a rewrite.
- [ ] New InstallationId is not used until persistence/readback succeeds.

### Hotstrings

- [ ] Short replacement.
- [ ] 200+ character replacement.
- [ ] Multiline replacement.
- [ ] Replacement containing `{Tab}`/`{Left}` or another supported key command.
- [ ] `{{datum}}` and `{{tijd}}` expansion.
- [ ] Existing clipboard contents survive hotstring use unchanged.
- [ ] Save/edit/delete with AutoSave.
- [ ] Backup/temp/atomic write path.
- [ ] Legacy `.txt` import behavior.

### Packages

- [ ] Package catalogue loads.
- [ ] Large spelling package opens acceptably.
- [ ] Enable/disable package and item.
- [ ] Personal conflict -> `Overruled` by default.
- [ ] Explicit package priority -> `Voorrang`.
- [ ] Package/package duplicate -> `Conflict`.
- [ ] Save package item as personal copy.
- [ ] Closing package manager during/after load remains safe.

### Telephony

- [ ] Registration/link-code request.
- [ ] Successful phone linking.
- [ ] Refresh cooldown/countdown.
- [ ] Poll loop continues without overlapping requests.
- [ ] Poll loop recovers after the known stop/restart scenarios.
- [ ] Call is blocked when no phone is linked.
- [ ] Linking call remains allowed.
- [ ] External Dutch number normalization.
- [ ] Internal four-digit number path.
- [ ] Speed dial from main UI and tray menu.

### Call action / SMS

- [ ] All four `Belactie` states behave correctly.
- [ ] SMS is not offered when no valid local SMS action exists.
- [ ] SMS is offered only for eligible mobile numbers.
- [ ] Single SMS action config remains compatible.
- [ ] Multiple SMS action config and selector work.
- [ ] Dialog initially paints the selected button correctly.
- [ ] Left/right selection works.
- [ ] Enter activates the visually selected button.
- [ ] Existing Edge foreground tab path.
- [ ] Existing Edge background tab path through UIA.
- [ ] Missing tab -> configured URL opens.
- [ ] Telephone field is filled through UIA.
- [ ] JavaScript fallback still works if needed.
- [ ] No obsolete "number filled" success notification is shown.
- [ ] DocBot does not send the SMS automatically.

### Help / UI / tray

- [ ] Sidebar navigation.
- [ ] Help accordions and clickable page links.
- [ ] Custom notification window appears on managed Windows where TrayTip is unavailable.
- [ ] Main window/tray state refreshes after telephony changes.
- [ ] Start active/background/minimized behavior.

### Diagnostics / problem reporting

- [ ] Baseline debug log remains available.
- [ ] Developer debug window restriction remains intentional.
- [x] Integrated problem-reporting and extended-logging validation completed on RC2.

### Deployment/update

- [ ] Compile final RC executable with the authorized local config.
- [ ] `Build-EPD_Machine.bat` behavior on intended folder layout.
- [ ] `signal.txt` shutdown/update flow.
- [ ] Executable replacement and byte verification.
- [ ] Restart task preserves active/background/minimized state.
- [ ] Update signal is removed on both success and failure.

---

## P1 — Finalize stable 2.2 release

Only after RC2 is explicitly accepted.

- [ ] On the release branch, set `AppVersion` from the final `2.2-rc.N` to stable `2.2` in the definitive release commit.
- [ ] Change README status from release candidate/development wording to stable 2.2 wording.
- [ ] Finalize `### 2.2` in the README Changelog; it remains the only release-history source.
- [ ] Verify the README `Telemetrie` section exactly matches the shipped payload and intervals.
- [ ] Verify license/documentation references identify the current project license and bundled third-party licenses correctly.
- [ ] Merge the release PR into `main` with **Create a merge commit**.
- [ ] Create annotated tag `v2.2` on the stable release commit.
- [ ] Push/verify the tag on `origin`.
- [ ] Bring release-only fixes back to `develop` via PR/merge commit.
- [ ] Start the next development version on `develop` according to the normal version scheme.

---

## P1 — Change user-data profile selection to build mode

### Desired rule

Replace the current prerelease-suffix-based Documents-profile selection with a rule based on stability and whether the script is compiled:

```text
stable                     -> Documents\DocBot
compiled non-stable        -> Documents\DocBot-test
noncompiled non-stable     -> Documents\DocBot-dev
```

Stable has priority: a stable numeric `AppVersion` uses `DocBot` regardless of whether it is compiled. For every non-stable version, `A_IsCompiled` determines whether the test or development profile is used. The prerelease label (`-dev`, `-rc`, feature/fix name) must no longer independently choose `DocBot-test` versus `DocBot-dev`.

### Rationale

- A compiled prerelease is a test of the deliverable form and should share the central `DocBot-test` profile regardless of whether it came from `develop`, an RC branch, or a feature/fix branch.
- A noncompiled prerelease is source-level development and should remain isolated in `DocBot-dev`.
- `AppVersion` continues to identify branch/release state for versioning; it should not by itself determine the non-stable storage profile.

### Implementation scope

- [ ] Change the profile-selection logic in `DocBot.ahk` (currently centered around `GetUserDataProfile(AppVersion)`) so it incorporates stability plus `A_IsCompiled`.
- [ ] Keep the existing one-time bootstrap chain unless implementation review finds a concrete reason to change it: missing `DocBot-test` copies from `DocBot`; missing `DocBot-dev` prefers `DocBot-test`, otherwise `DocBot`; never overwrite an existing destination profile.
- [ ] Update nearby source comments so they no longer describe `-dev`/`-rc` versus other prerelease suffixes as the profile selector.
- [ ] Update `README.md` wherever the old profile rule is described.
- [ ] Update the `Gebruikersprofielen` rule in both `AGENTS.md` and `CLAUDE.md`; make explicit that build form, not feature/RC suffix, selects the non-stable profile.
- [ ] Update `docs/PROJECT_CONTEXT.md` and `docs/ARCHITECTURE.md` to the new invariant/data-flow.
- [ ] Add/supersede the corresponding storage-profile decision in `docs/DECISIONS.md` rather than silently erasing the old rationale.
- [ ] Revisit this TODO and any acceptance-test wording that still assumes suffix-only profile selection.
- [ ] Do not change the branch-version scheme (`2.2-dev.N`, `2.2-<branch>.N`, `2.2-rc.N`, stable `2.2`).
- [ ] Do not treat package-cache behavior under `%LocalAppData%` as part of this change unless explicitly approved; this task concerns Documents/config/user-data profile selection.
- [ ] Telemetry payload, fields and interval should remain unchanged; only its `settings.ini` location follows the selected user profile. Update telemetry documentation only if the implementation changes telemetric behavior beyond that.

### Required test matrix

- [ ] Stable `2.2`, compiled -> `Documents\DocBot`.
- [ ] Stable `2.2`, noncompiled -> `Documents\DocBot`.
- [ ] `2.2-dev.N`, compiled -> `Documents\DocBot-test`.
- [ ] `2.2-rc.N`, compiled -> `Documents\DocBot-test`.
- [ ] Feature/fix prerelease such as `2.2-example.1`, compiled -> `Documents\DocBot-test`.
- [ ] `2.2-dev.N`, noncompiled -> `Documents\DocBot-dev`.
- [ ] `2.2-rc.N`, noncompiled -> `Documents\DocBot-dev`.
- [ ] Feature/fix prerelease, noncompiled -> `Documents\DocBot-dev`.
- [ ] Existing `DocBot-test` and `DocBot-dev` directories are never repopulated/overwritten merely because selection rules changed.
- [ ] Stored hotstring/settings/package/speeddial paths still migrate or resolve correctly in the selected profile.

### Version/preflight requirement when implementing

This is a real `DocBot.ahk` behavior change, so implement it on its own feature/fix branch from the then-current `develop`. Every commit that changes `DocBot.ahk` must update the branch-specific `AppVersion` in that same commit. README/changelog need must be assessed in the same commit sequence; telemetry documentation only changes if telemetry behavior/config/payload changes.

---

## P1 — Add a reliable AutoHotkey v2 syntax smoke check

### Why

Recent extended-logging development repeatedly produced syntax errors that were discoverable only when the owner ran the code. Source review and generic diff checks are not enough.

### Goal

Create a lightweight validation path that can fail a PR before manual testing when `DocBot.ahk` or another first-party `.ahk` file cannot be parsed/compiled as AutoHotkey v2.

### Constraints

- [ ] Validation must actually use AutoHotkey v2 / Ahk2Exe semantics, not a regex pretending to be a parser.
- [ ] Do not require real internal telephony secrets for a pure syntax check.
- [ ] Do not expose `DocBot.local.ahk` secrets in CI logs/artifacts.
- [ ] If CI cannot safely compile the real app because local configuration is required, consider a safe test configuration/template specifically for parse/compile validation.
- [ ] Keep Windows-specific validation explicit; macOS git tooling alone cannot validate AHK runtime behavior.

---

## P1 — Standardize the local engineering workflow

The project has suffered from GitHub connector limitations on the very large `DocBot.ahk` file and temporary GitHub Actions workflows used as an editing workaround.

Preferred workflow to document/adopt:

- [ ] local clone for source editing;
- [ ] `git fetch --prune` before branch work;
- [ ] branch from current `develop` unless explicit hotfix;
- [ ] inspect `git status` before pull/switch;
- [ ] commit or stash intentional local changes before `git pull`;
- [ ] explicit per-commit preflight for AppVersion/README/telemetry docs;
- [ ] push branch normally;
- [ ] use GitHub PRs for review/integration;
- [ ] perform Windows AHK functional validation separately when developing from a Mac.

Avoid workflow-as-editor/temporary trigger PRs unless normal git/connector methods are genuinely unavailable.

---

## P1 — Keep project handover docs current

These four `docs/` files are intended to replace project-conversation dependence for future agents.

After significant architectural or release changes:

- [ ] update `PROJECT_CONTEXT.md` if the product/release situation changes;
- [ ] update `ARCHITECTURE.md` when component/data-flow/storage architecture changes;
- [ ] add/supersede a decision in `DECISIONS.md` rather than silently rewriting history;
- [ ] remove completed tasks or mark them resolved in this file;
- [ ] continue to treat `AGENTS.md`/`CLAUDE.md` as the authoritative operational rules agents must read before writes.

Do not copy end-user changelog content into these docs verbatim; link concepts and rationale instead.

---

## P2 — Introduce targeted automated tests where practical

There is currently no conventional `tests/` directory. High-value testable areas that do not require a live hospital environment include:

- [ ] stable/non-stable + compiled/noncompiled -> user-profile selection;
- [ ] telephone-number normalization;
- [ ] hotstring execution-mode selection;
- [ ] dynamic token expansion;
- [ ] JSON migration/default-addition idempotency;
- [ ] package conflict resolution and status calculation;
- [ ] telemetry payload serialization/redaction boundaries;
- [ ] telemetry InstallationId persistence state machine using controlled file conditions;
- [ ] parsing/validation of package manifest and package files.

Keep live telephony/Edge/UIA tests as integration/manual tests unless a realistic Windows harness is introduced.

---

## P2 — Make migration behavior easier to inspect

There is no `migrations/` directory; migrations are embedded in `DocBot.ahk` and keyed by schema versions.

Without changing behavior immediately, consider documenting or extracting a clearer migration registry so an engineer can answer:

- which schema version added which field/default;
- which old filenames/formats are still supported;
- which migrations are safe to remove only after a defined compatibility window.

Do not move migration code during the 2.2 release just for cleanliness.

---

## P2 — Consider gradual modularization after 2.2

`DocBot.ahk` is large. Modularization could eventually improve maintainability, but it is **not** a safe last-minute release task.

Possible future seams:

- storage/migrations;
- hotstring/package engine;
- telephony;
- SMS/UIA integration;
- diagnostics/problem reporting;
- GUI rendering helpers.

Before extracting a subsystem, account for:

- AutoHotkey top-level initialization order;
- global GUI control references;
- callback binding/lifetime;
- dynamic hotstring registration;
- `FileInstall` compile behavior;
- local-config validation;
- AppVersion/profile behavior.

Prefer small behavior-preserving extractions with Windows regression tests over a rewrite.

---

## Resolved issues / do not reintroduce

These problems are important historical context but are not open TODOs unless they regress.

- **Daily/new telemetry identity due failed persistence:** fixed by reading an existing ID without rewrite and confirming new ID persistence before use, with retries.
- **Broad startup storage writeability gate:** intentionally removed because temporary OneDrive unavailability should not block all DocBot functionality.
- **Third-party root include shims:** transitional approach removed; use direct `ThirdParty/...` include paths.
- **Missing third-party license grouping:** libraries now live in dedicated ThirdParty directories with original license files.
- **SMS prototype file:** the standalone POC was removed once the feature was integrated; do not restore it as active source.
- **Initial call/SMS dialog button rendering:** fixed with repaint/redraw after showing the dialog.
- **Keyboard selection in call/SMS dialog:** implemented with left/right and Enter.
- **Redundant success notification after SMS telephone fill:** intentionally removed.
- **`TrayTip()` reliability:** replaced for important notifications because managed Windows group policy can suppress it.
- **GET telephony requests:** replaced by POST.
- **Shared telephony XHR reference:** replaced by independent request objects.
- **Fixed-interval long polling:** replaced by chained polling after response completion.
- **Clipboard-based hotstring expansion:** deliberately removed/prohibited.
- **Extended-logging integration status in durable docs:** synchronized with the integrated `develop`/RC2 source; obsolete feature-branch promotion tasks were removed while RC2 acceptance tests remain open.
- **Integrated problem reporting on RC2:** the dedicated compiled-Windows validation checklist was completed by the project owner on 2026-08-09, including consent/privacy boundaries, session behavior, diagnostic content, ZIP creation, and Outlook/manual fallback paths.

---

## Agent start checklist

Before picking any TODO:

- [ ] read `AGENTS.md` completely from the target branch;
- [ ] read `CLAUDE.md` if present;
- [ ] inspect current branch and remote status;
- [ ] inspect current AppVersion;
- [ ] check open PRs/branches because this file is a dated snapshot;
- [ ] state which repository rules apply before the first write;
- [ ] do not write directly to `main` or `develop`;
- [ ] keep real local configuration/secrets outside Git;
- [ ] before every commit, re-check AppVersion coupling, README/changelog need, and telemetry-documentation need.
