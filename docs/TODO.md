# DocBot — TODO

_Last updated: 2026-08-10. This file is a handover backlog, not a promise that every lower-priority idea must be implemented. Re-check repository/PR state before acting._

## Priority legend

- **P0** — blocks the current 2.2 release path or risks a broken build.
- **P1** — should be completed before/around 2.2 release or immediately afterwards.
- **P2** — valuable engineering improvement; not a reason to destabilize the current release.

---

## P0 — Full 2.2 RC3 acceptance test

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

Only after the current RC3 is explicitly accepted.

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

## P1 — Make HTTPS mandatory for telephony and SMS URLs

An exploratory test on 2026-08-09 showed that changing the local telephony
`BaseUrl` from `http://` to `https://` still delivered a registration/link
code and successfully established a test call. Treat this as evidence that the
HTTPS migration path is viable, not yet as complete acceptance or proof for
every managed Windows workstation.

### Application and documentation

- [x] Change `DocBot.local.example.ahk` so the telephony `BaseUrl` example uses
  `https://`.
- [ ] Extend `ValidateLocalConfiguration()` to reject a telephony `BaseUrl`
  that does not use HTTPS. Do not add a production certificate-validation
  bypass or silent HTTP fallback.
- [ ] Extend `ValidateSmsCallActionItem()` to reject every `SmsCallAction.Url`
  that does not use HTTPS. Do not open or fill an HTTP SMS page.
- [ ] Keep registration, event polling, and dialing on the same validated HTTPS
  base URL unless the server contract is deliberately redesigned.
- [ ] Document the HTTPS-only production invariant for telephony and SMS in `README.md`,
  `AGENTS.md`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, and where relevant
  `docs/REGULATORY_ASSESSMENT.md` and `docs/DECISIONS.md`.
- [ ] Confirm separately whether the server provides strong client/server
  authentication; TLS transport encryption alone does not establish client
  authorization. Record any additional authentication work as an explicit
  scoped task.

### Infrastructure dependencies

- [ ] Confirm that the production hostname, certificate subject/SAN, full
  certificate chain, TLS version, and listening port are correct for managed
  Windows workstations.
- [ ] Confirm that the issuing root/intermediate CA certificates are deployed
  through the normal hospital trust-store management and that no client needs
  to ignore certificate errors.
- [ ] Confirm that reverse-proxy or server timeouts support the long-polling
  event endpoint.
- [ ] Assign ownership and monitoring for certificate renewal/expiry.
- [ ] After the HTTPS rollout is accepted, disable the unsecured HTTP listener
  rather than relying on an HTTP-to-HTTPS redirect. Coordinate this with the
  telephony/server owner; it is not a DocBot-only change.

### Acceptance evidence

- [x] Exploratory HTTPS test: registration/link code received.
- [x] Exploratory HTTPS test: test call successfully established.
- [ ] Registration/link-code request succeeds in a compiled test build on a
  representative managed Windows workstation.
- [ ] Event polling remains active over time, does not overlap, and recovers
  after the known stop/restart scenarios through HTTPS.
- [ ] Linking and a controlled call to a designated test number succeed.
- [ ] Certificate-name, trust-chain, expiry, and TLS failures are rejected and
  produce a clear, non-sensitive diagnostic instead of falling back to HTTP.
- [ ] A telephony or SMS URL using `http://` is rejected during configuration
  validation with a clear, non-sensitive error.
- [ ] The final release/preflight checklist records the HTTPS base URL and
  certificate validation result without recording the confidential hostname,
  endpoints, telephone numbers, or certificate private material in Git.

This is a real `DocBot.ahk` behavior change. Implement it on a dedicated
feature/fix branch from the then-current `develop`, update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`, and validate the
compiled result on Windows and the internal network before integration.

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

## P1 — Propagate the AutoHotkey v2 syntax smoke check to `develop`

### Status

Implemented and validated. `.github/workflows/ahk-syntax-check.yml` runs
`AutoHotkey64.exe /Validate` on a `windows-latest` GitHub Actions runner
against `DocBot.ahk` (which pulls in the rest of the first-party source via
`#Include`), using `DocBot.local.example.ahk` as the safe CI configuration
so no real local secrets are needed or exposed in logs.

Triggers: pull requests touching `.ahk` files (any base branch), pushes to
`develop`, and `workflow_dispatch` — the latter only works once the
workflow file exists on the repository's default branch.

Merged into `release/2.2-rc` via PR #19 (merge commit `2ee42b6`) and
validated there:

- a clean `DocBot.ahk` passes;
- a real parse-time syntax error is reported as a failure within roughly a
  minute.

Implementation note: `AutoHotkey64.exe /Validate` can still show a blocking
error dialog on some parse errors even with `/ErrorStdOut`, which would
hang a CI runner indefinitely if the step simply waited on the process.
The workflow therefore starts the process without `-Wait`, calls
`WaitForExit(60000)` itself, force-kills the process and reports a clear
failure if it has not exited within 60 seconds, with `timeout-minutes: 5`
on the job as a hard backstop.

### Remaining work

- [ ] The workflow currently exists only on `release/2.2-rc`, not on
  `develop` or `main`. Add it to `develop` too (via a normal feature/fix
  branch and PR) so it protects all new work, not only the current release
  line, and will reach `main` through the normal release merge.
- [ ] Decide whether the `pull_request` trigger should stay unscoped (any
  base branch) or be limited to `develop`/`release/*`.
- [ ] Reconsider relying on `workflow_dispatch` once the workflow exists on
  the default branch; it cannot be triggered manually from a non-default
  branch.

---

## P1 — Limit local standard diagnostics to seven days

Implement automatic cleanup of standard diagnostic log entries older than
seven days.

- [ ] Remove entries older than seven days from both the active standard log
  and the rotated `.oud` log without relying only on file modification time.
- [ ] Preserve the existing redaction and approximately 2 MB size-rotation
  behavior.
- [ ] Ensure malformed or legacy log lines and cleanup failures do not block
  application startup.
- [ ] Verify on managed Windows that recent entries remain available, expired
  entries are removed and extended-session logging keeps its separate
  lifecycle.
- [ ] Keep `README.md` and `docs/DATA_PROTECTION.md` synchronized with the
  implemented behavior.

This changes `DocBot.ahk` behavior. Implement it on a dedicated feature/fix
branch from the then-current `develop` and update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`.

---

## P1 — Remove temporary problem-report artifacts

Complete the lifecycle of the ZIP and temporary files created during problem
reporting.

- [ ] On cancellation, remove every ZIP, extracted working directory and
  temporary extended log created for that report session.
- [ ] After successful attachment to an Outlook draft, remove the local ZIP
  only after verifying that Outlook has safely taken over the attachment.
- [ ] For the manual fallback, keep the ZIP available until the user has had a
  usable opportunity to attach it, then provide an explicit completion/cleanup
  path and a safe cleanup fallback for abandoned artifacts.
- [ ] Verify that cancelling at each stage and closing DocBot cannot leave
  sensitive report artifacts behind indefinitely.
- [ ] Update `README.md` and `docs/DATA_PROTECTION.md` to the implemented
  lifecycle.

This changes `DocBot.ahk` behavior. Implement it on a dedicated feature/fix
branch from the then-current `develop` and update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`.

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

## P2 — Add a user instruction for safe hotstring content

Create and maintain an end-user instruction for personal hotstrings. The
instruction must:

- [ ] explain that hotstrings are intended for generic, reusable text;
- [ ] prohibit patient-identifying and patient-specific content in
  `hotstrings.json`;
- [ ] distinguish prohibited patient-specific content from generic clinical
  formulations that are not linked to an identifiable patient;
- [ ] explain that a name, telephone number, e-mail address or signature of
  the employee can be personal data and remains subject to organizational
  policy;
- [ ] explain that DocBot cannot technically determine whether free text
  contains patient-specific information;
- [ ] identify where the instruction is presented to users and who owns its
  review and maintenance.

Align the instruction with `docs/DATA_PROTECTION.md` and reassess whether it
must also appear in the README, in-product help or organizational onboarding
before release.

---

## P2 — Reassess the telemetry username after the startup phase

The Windows username currently supports targeted troubleshooting during the
startup phase, for example when telephony is not activated or when a local
installation identity behaves unexpectedly because OneDrive was not yet
synchronized. Telemetry was designed for data minimization from the start:
the payload already carries a pseudonymous, randomly generated installation
ID rather than relying on directly identifying data, and the username is a
deliberately temporary addition on top of that ID, not a substitute for a
missing pseudonymous identifier.

- [ ] Define who decides when the startup phase has ended and record an
  objective review date or exit criterion.
- [ ] Reassess whether targeted support still requires the Windows username.
- [ ] If it is no longer necessary, remove the username from the payload.
  The installation ID already present in the payload continues to serve as
  the less-identifying mechanism for the remaining telemetry purposes; no
  new pseudonymization mechanism needs to be designed.
- [ ] Do not reuse the username for performance, attendance or individual
  work-behavior monitoring.
- [ ] Update the README telemetrie notice and `docs/DATA_PROTECTION.md` in the
  same change as any payload modification.

Changing the payload requires explicit approval from the project owner. A
change to `DocBot.ahk` must follow the branch-specific `AppVersion` rule.

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
- **Extended-logging integration status in durable docs:** synchronized with the integrated `develop`/RC2 source; obsolete feature-branch promotion tasks were removed while broader release-candidate acceptance remains open.
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
