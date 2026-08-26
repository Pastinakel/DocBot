# DocBot — TODO

_Last updated: 2026-08-25. This file is a handover backlog, not a promise that every lower-priority idea must be implemented. Re-check repository/PR state before acting._

## Priority legend

- **P0** — blocks the current release path or risks a broken build.
- **P1** — should be completed before/around the current release or immediately afterwards.
- **P2** — valuable engineering improvement; not a reason to destabilize the current release.

---

## P0 — Release plan: finalize stable DocBot 2.3 (completed — DocBot 2.3 released)

DocBot 2.3 shipped: `main` is tagged `v2.3` (merge commit `dbe4c52`, PR #51).
This section is kept as a record of the release-finalization plan and what
it covered; all items below were completed.

### Final status

- `main` is stable **DocBot 2.3**, merged from `release/2.3-rc` via PR #51
  (merge commit `dbe4c52`) and tagged `v2.3` on that commit.
- `release/2.3-rc` and `release/2.3-finalize` have been deleted after
  merging; their content lives on in `main`/`develop` history and tag
  `v2.3`.
- The release-only fixes (CRLF line-ending enforcement D-057, removal of
  the `attrib`-based folder pin D-058, and the pre-asked build questions)
  were brought back into `develop` via PR #52
  (`chore/bring-back-2.3-to-develop`, mirroring PR #28 for 2.2).
- `develop` started the next development line at `AppVersion = 2.4-dev.1`
  (direct commit on `develop`, mirroring commit `35d3937` after the 2.2
  release).
- The full feature/fix set for 2.3 is recorded in the README
  `### 2.3 — Huidige stabiele release` changelog section — treat that
  section, not this file, as the authoritative feature list for the
  release notes.

### Remaining blockers before merging `release/2.3-rc` into `main`

- [x] "P1 — Baseline debug output for repeated SMS window/tab reopening"
  (below): the project owner attempted to reproduce the reopening issue on
  a real compiled build and could not trigger it. The baseline logging that
  would capture the decision path if/when it does recur is in place and
  ships as-is. **Decision: does not block the release** — the remaining
  "Investigate" line becomes a known follow-up, only actionable if/when the
  issue actually recurs in the field with the new logging active.
- [x] `tests/SelfTests.ahk` confirmed via both an interpreted
  `AutoHotkey64.exe DocBot.ahk --selftest` run (24/24 on 2026-08-19) and a
  compiled `DocBot.exe --selftest` run (2026-08-25): the console showed no
  output, as expected for a GUI-subsystem executable (`docs/DECISIONS.md`
  D-053, `tests/README.md`), but `%TEMP%\docbot-selftest-results.txt`
  recorded "32 tests, 32 geslaagd, 0 mislukt". The higher count than the
  24/24 interpreted run is expected, not a discrepancy: `TestGetUserDataProfile`
  added 8 assertions for the D-056 profile-selection matrix after that
  24/24 run was recorded.
- [x] The hotstring-content Help instruction (D-045): confirmed good on a
  compiled build (fifth accordion section, Tekstvervanging hint in both
  editor states, Hotstrings/Telefonie/Over card bottom alignment).
- [x] Both remaining rows of the profile-selection test matrix (D-056)
  validated on Windows: existing `DocBot-test`/`DocBot-dev` folders are not
  repopulated/overwritten by the new selection logic, and stored
  hotstring/settings/package/speeddial paths resolve correctly in the
  selected profile.
- [x] `claude/todo-itemcount-package-check` (filed 2026-08-25 against
  `develop`, adds a P2 TODO item only — see below): opened as its own
  docs-only PR into `develop`, PR #48, per project-owner decision, rather
  than folding it into next-cycle backlog silently. Merge PR #48 before
  treating `develop`/`release/2.3-rc` docs as back in sync.
- [x] Confirmed: no other feature/fix branches are unmerged against
  `develop`/`release/2.3-rc` besides the one above.

Every item in this list is now resolved; see "Finalizing the stable
release" below for the remaining work.

### Acceptance checklist for what changed since 2.2

Run this in addition to, not instead of, the full 2.2 RC3 regression
checklist above — that checklist still covers unchanged behavior end to
end.

- [x] Compiled build reads its `packages` folder from next to the
  executable (`A_ScriptDir`) on the correct network share; a local-copy
  launch (e.g. via Ivanti) still honors `LocalConfig["Packages"]["ShareDir"]`
  as an explicit override (D-048/D-049).
- [x] Package manifest entries with only `id`/`file` still load correctly;
  an optional package `owner` field displays next to the package name in
  **Pakketten** (D-054).
- [x] Closing the package manager while conflict status for a large package
  is still being calculated no longer errors (D-051).
- [x] `Build-EPD_Machine.bat` populates a `packages` folder next to every
  deployed executable, asking before overwriting an existing one (D-052);
  it asks all interactive questions before compilation starts, where Enter
  means "Ja" and only an explicit "N" means "Nee"; and it runs correctly
  from a fresh checkout now that `.gitattributes` forces CRLF (D-057).
- [x] Non-stable installs pick `DocBot-test` when compiled and `DocBot-dev`
  when run from source, regardless of the `-dev`/`-rc`/feature-name
  prerelease label (D-056) — validated on Windows. `DocBot.ahk --selftest`
  passed both interpreted (24/24) and compiled (32/32, see blocker above).
- [x] Telephony `BaseUrl` and every `SmsCallAction.Url` are rejected at
  startup when not `https://` (D-043) — re-confirm once more on the final
  RC build.
- [x] An SMS page configured with `TextFieldId` offers a per-page multiline
  default text under **Instellingen > SMS actie** (hard enters preserved)
  that is filled into the message field after the phone number (D-055).
- [x] The standard log/live debug window now shows, without an active
  extended-logging session, which SMS window/tab path was attempted and
  why (`RunSmsCallAction()` and friends). Confirmed present; the actual
  reopening issue itself was not reproducible on a real compiled build
  (see "P1 — Baseline debug output..." below).
- [x] Standard log entries older than seven days (including legacy
  pre-"v2" lines) are pruned from both the active log and `.oud`; the
  ~2 MB size-rotation behavior is unaffected (D-044).
- [x] Abandoned problem-report directories/extended logs older than seven
  days are cleaned up automatically, with the "Probleemrapportmap
  opschonen" log line appearing even when nothing was found; cancel/
  Outlook/manual-fallback cleanup behaves as documented.
- [x] DocBot starts without triggering an application-whitelisting security
  dialog on a hardened workstation now that the `attrib`-based folder pin
  is removed entirely (D-058).
- [x] `docs/MIGRATIONS.md` still matches actual schema-version behavior for
  all four loaders.

### Finalizing the stable release (per the branch/version rules in `CLAUDE.md`/`AGENTS.md`)

- [x] On `release/2.3-rc`, set `global AppVersion` from the final
  `2.3-rc.3` to stable `2.3` in the definitive release commit
  (`release/2.3-finalize`, merged into `release/2.3-rc` via PR #50).
- [x] Update README status wording from release-candidate/"in ontwikkeling"
  to stable 2.3 wording (same PR #50).
- [x] Finalize `### 2.3` in the README Changelog (dropped
  "— In ontwikkeling", now "— Huidige stabiele release"; same PR #50).
- [x] Verified the README `Telemetrie` section still exactly matches the
  shipped payload and interval — no payload change shipped in 2.3.
- [x] Verified license/documentation references (PolyForm Noncommercial plus
  the ThirdParty MIT notices) — still accurate, unchanged.
- [x] Opened a pull request from `release/2.3-rc` into `main` (PR #51);
  merged with **Create a merge commit** (`dbe4c52`) after project-owner
  review and approval.
- [x] Created the annotated tag `v2.3` on the stable release commit
  (`dbe4c52`), after separate explicit go-ahead from the project owner.
- [x] Pushed the tag to `origin` and confirmed it is visible there.
- [x] Brought the release-only fixes back into `develop` via PR #52
  (`chore/bring-back-2.3-to-develop`, merge commit, mirrors PR #28 for 2.2).
- [x] Started the next development version on `develop`
  (`AppVersion = 2.4-dev.1`, direct commit, mirroring commit `35d3937`)
  once the merge-back above landed.
- [x] Deleted the temporary release branches (`release/2.3-rc`,
  `release/2.3-finalize`) after merging; their content lives on in
  `main`/`develop` history and tag `v2.3`.
- [x] Updated `docs/PROJECT_CONTEXT.md` §3 (branch/release status) and
  `AGENTS.md`/`CLAUDE.md`/`docs/DECISIONS.md` D-005 version-scheme examples
  to the 2.4 cycle, and `docs/ARCHITECTURE.md`/`docs/DATA_PROTECTION.md`
  version anchors to `v2.3`, in a docs-only sync PR to `main`
  (`docs/sync-main-after-2.3`, mirroring PR #29 for 2.2). Also updated
  `docs/REGULATORY_ASSESSMENT.md` (new SMS-default-text autonomous action,
  D-055; resolved hotstring-instruction items, D-045) in the same PR.

---

## P0 — Full 2.2 RC3 acceptance test (completed — DocBot 2.2 released)

DocBot 2.2 shipped: `main` is tagged `v2.2` (merge commit `a156dfe`, PR #27).
This checklist is kept as a record of what the RC3 acceptance test covered;
all items below were confirmed before the release.

At minimum, validate the following on the managed Windows environment and, where required, on the internal hospital network.

### Startup / storage

- [x] Stable/test/dev profile selection is correct for the RC version (`DocBot-test`).
- [x] Existing profile data is not overwritten by bootstrap copying.
- [x] `attrib -U +P` failure does not block startup.
- [x] Missing/temporarily unavailable telemetry storage does not block core app functionality.
- [x] Existing telemetry InstallationId is used without a rewrite.
- [x] New InstallationId is not used until persistence/readback succeeds.

### Hotstrings

- [x] Short replacement.
- [x] 200+ character replacement.
- [x] Multiline replacement.
- [x] Replacement containing `{Tab}`/`{Left}` or another supported key command.
- [x] `{{datum}}` and `{{tijd}}` expansion.
- [x] Existing clipboard contents survive hotstring use unchanged.
- [x] Save/edit/delete with AutoSave.
- [x] Backup/temp/atomic write path.
- [x] Legacy `.txt` import behavior.

### Packages

- [x] Package catalogue loads.
- [x] Large spelling package opens acceptably.
- [x] Enable/disable package and item.
- [x] Personal conflict -> `Overruled` by default.
- [x] Explicit package priority -> `Voorrang`.
- [x] Package/package duplicate -> `Conflict`.
- [x] Save package item as personal copy.
- [x] Closing package manager during/after load remains safe.

### Telephony

- [x] Registration/link-code request.
- [x] Successful phone linking.
- [x] Refresh cooldown/countdown.
- [x] Poll loop continues without overlapping requests.
- [x] Poll loop recovers after the known stop/restart scenarios.
- [x] Call is blocked when no phone is linked.
- [x] Linking call remains allowed.
- [x] External Dutch number normalization.
- [x] Internal four-digit number path.
- [x] Speed dial from main UI and tray menu.

### Call action / SMS

- [x] All four `Belactie` states behave correctly.
- [x] SMS is not offered when no valid local SMS action exists.
- [x] SMS is offered only for eligible mobile numbers.
- [x] Single SMS action config remains compatible.
- [x] Multiple SMS action config and selector work.
- [x] Dialog initially paints the selected button correctly.
- [x] Left/right selection works.
- [x] Enter activates the visually selected button.
- [x] Existing Edge foreground tab path.
- [x] Existing Edge background tab path through UIA.
- [x] Missing tab -> configured URL opens.
- [x] Telephone field is filled through UIA.
- [x] JavaScript fallback still works if needed.
- [x] No obsolete "number filled" success notification is shown.
- [x] DocBot does not send the SMS automatically.

### Help / UI / tray

- [x] Sidebar navigation.
- [x] Help accordions and clickable page links.
- [x] Custom notification window appears on managed Windows where TrayTip is unavailable.
- [x] Main window/tray state refreshes after telephony changes.
- [x] Start active/background/minimized behavior.

### Diagnostics / problem reporting

- [x] Baseline debug log remains available.
- [x] Developer debug window restriction remains intentional.
- [x] Integrated problem-reporting and extended-logging validation completed on RC2.

### Deployment/update

- [x] Compile final RC executable with the authorized local config.
- [x] `Build-EPD_Machine.bat` behavior on intended folder layout.
- [x] `signal.txt` shutdown/update flow.
- [x] Executable replacement and byte verification.
- [x] Restart task preserves active/background/minimized state.
- [x] Update signal is removed on both success and failure.

---

## P1 — Finalize stable 2.2 release (done)

- [x] On the release branch, set `AppVersion` from the final `2.2-rc.N` to stable `2.2` in the definitive release commit.
- [x] Change README status from release candidate/development wording to stable 2.2 wording.
- [x] Finalize `### 2.2` in the README Changelog; it remains the only release-history source.
- [x] Verify the README `Telemetrie` section exactly matches the shipped payload and intervals.
- [x] Verify license/documentation references identify the current project license and bundled third-party licenses correctly.
- [x] Merge the release PR into `main` with **Create a merge commit** (PR #27, merge commit `a156dfe`).
- [x] Create annotated tag `v2.2` on the stable release commit.
- [x] Push/verify the tag on `origin`.
- [x] Bring release-only fixes back to `develop` via PR/merge commit (PR #28).
- [x] Start the next development version on `develop` according to the normal version scheme (`AppVersion = 2.3-dev.1`, direct commit on `develop`).

The temporary release branches (`release/2.2-rc`, `release/2.2-finalize`,
`docs/rc3-acceptance-checklist`, `chore/bring-back-2.2-to-develop`) have all
been deleted after merging; their content lives on in `main`/`develop`
history and tag `v2.2`.

---

## P1 — Baseline debug output for repeated SMS window/tab reopening (not release-blocking; attempted reproduction inconclusive)

Reported by the project owner (2026-08-19): sometimes a new SMS Edge
window/tab is opened even though a matching tab is already open on the
correct page. The project owner wants to see, in the always-on developer
debug window/standard log, which path `RunSmsCallAction()` actually took
and why the earlier ones were skipped — not only during a consented
extended-logging session.

### Root cause of the diagnostic gap

`RunSmsCallAction()` (`DocBot.ahk`) tries three paths in order:

1. `ActivateSmsEdgeWindowByTitle()` — `WinActivate`/`WinWaitActive` on
   `smsConfig["WindowTitle"]`;
2. `ActivateSmsEdgeTabByTitle()` — enumerates usable Edge windows
   (`GetUsableEdgeBrowserWindows()`) and calls UIA `TabExist()` per window;
3. `OpenSmsPage()` — URL fallback that starts a new `msedge.exe` process.

Every decision point in these four functions currently logs only through
`ExtendedDebugLog()`, which is gated behind explicit user consent and an
active problem-report session (see `docs/PROJECT_CONTEXT.md` §4.9). In
normal use nothing about *why* path 1/2 failed and path 3 (new
window/tab) triggered reaches the baseline `debug.log`/live debug window
at all, so the project owner cannot currently see why a matching tab was
missed.

### Scope

- [x] Add baseline `DebugLog()` calls (not only `ExtendedDebugLog()`) at
  the decision points in `RunSmsCallAction()`,
  `ActivateSmsEdgeWindowByTitle()`, `ActivateSmsEdgeTabByTitle()`, and
  `OpenSmsPage()`: which path was attempted, whether it matched, and — for
  the tab-selection path — how many usable Edge windows/tabs were
  considered before falling through to the URL fallback that opens a new
  window/tab. Implemented on `claude/sms-window-baseline-logging`
  (`AppVersion 2.3-sms-heropen.1`). `ActivateSmsEdgeTabByTitle()` now also
  logs a baseline line for the previously-silent "no tab in this window,
  trying the next one" case per window, not only the final all-windows
  failure.
- [x] Keep `ExtendedDebugLog()` calls as-is for the already-detailed
  tracing; this is about promoting a summary of the same decision to the
  baseline log, not duplicating full detail there. Every new `DebugLog()`
  call sits next to its existing `ExtendedDebugLog()` call with a shorter
  message; no `ExtendedDebugLog()` call was changed or removed.
- [x] Follow existing redaction conventions: reuse `MaskSmsPhoneNumber()`
  for the number (already the case), and treat `WindowTitle` as the
  existing technical matching value it already is elsewhere in these
  logs — do not log the filled/entered SMS message text. `WindowTitle`
  values pass through the same `DebugLog()`/`SanitizeStandardLogText()`
  path as every other baseline log line, so an accidental URL/phone/
  internal-number match within a title would still be redacted; no new
  category of content is logged, so `docs/DATA_PROTECTION.md`/README were
  not changed beyond the changelog entry.
- [x] Investigate, using the new logging, plausible causes for a false
  "no matching tab" result on an already-open correct tab: title-match
  timing (`TabExist(targetTitle, 2, false)` timeout), a minimized/hidden
  window not enumerated by `GetUsableEdgeBrowserWindows()`, multiple Edge
  windows where the match is checked in the wrong one first and returns
  before scanning the rest, or the tab's title having changed (e.g. after
  page navigation) so it no longer matches the configured `WindowTitle`.
  The project owner attempted to reproduce the reopening issue on a real
  compiled build with the new baseline logging active (2026-08-25) and
  could not trigger it. Source review during implementation did not find a
  code-level bug in the loop/window-selection logic itself (a per-window
  non-match already falls through to the next window rather than
  aborting). No root cause is confirmed, but the diagnostic gap itself is
  closed: if the issue recurs, the baseline log now shows which path was
  tried and why, without needing a consented extended-logging session.
- [x] Update `docs/DATA_PROTECTION.md`/README only if the new baseline log
  lines add a new category of logged content beyond what is already
  documented for the standard log. Assessed: no new category (see above);
  only the README changelog was updated.

This changes `DocBot.ahk` behavior. Implemented on a dedicated feature/fix
branch from the then-current `develop` (this task was filed from
`claude/sms-window-reopen-bug-mmx5ln`); the branch-specific `AppVersion` was
updated in the same commit that changes `DocBot.ahk`. **Release decision
(2026-08-25):** this P1 entry does not block the 2.3 release — the
underlying reopening issue was not reproducible on a real compiled build,
and the observability gap it was filed to close is already shipped. Treat
any future recurrence as a new, separately filed bug report, now armed with
baseline logging from the start.

---

## P1 — Make HTTPS mandatory for telephony and SMS URLs (done)

An exploratory test on 2026-08-09 showed that changing the local telephony
`BaseUrl` from `http://` to `https://` still delivered a registration/link
code and successfully established a test call. Treat this as evidence that the
HTTPS migration path is viable, not yet as complete acceptance or proof for
every managed Windows workstation.

### Application and documentation

- [x] Change `DocBot.local.example.ahk` so the telephony `BaseUrl` example uses
  `https://`.
- [x] Extend `ValidateLocalConfiguration()` to reject a telephony `BaseUrl`
  that does not use HTTPS. Do not add a production certificate-validation
  bypass or silent HTTP fallback. Implemented on `claude/https-only-telephony-sms`
  (`AppVersion 2.3-https-telefonie.1`); see `docs/DECISIONS.md` D-043.
- [x] Extend `ValidateSmsCallActionItem()` to reject every `SmsCallAction.Url`
  that does not use HTTPS. Do not open or fill an HTTP SMS page. Implemented
  in the same change as above.
- [x] Keep registration, event polling, and dialing on the same validated HTTPS
  base URL unless the server contract is deliberately redesigned. Already
  true architecturally — `IPTConfig["URL"]` is built directly from the
  validated `BaseUrl`, so no separate per-call change was needed (D-043).
- [x] Document the HTTPS-only production invariant for telephony and SMS in `README.md`,
  `AGENTS.md`, `CLAUDE.md`, `docs/ARCHITECTURE.md`, and where relevant
  `docs/REGULATORY_ASSESSMENT.md` and `docs/DECISIONS.md`. Also updated
  `docs/DATA_PROTECTION.md` (not originally listed here, but it contained
  the same now-stale "code does not enforce HTTPS" wording in three places).
- [x] This is an infrastructure/organizational question, not a DocBot code
  task, and not something resolvable from within this repository or by the
  project owner alone: DocBot's own requests (`IPT_callNumber()`,
  `IPT_register()`) send no application-level credential today — no API
  key, bearer token, or client certificate, only an `Accept-Language`
  header — so as far as the code shows, the only current "authentication"
  is network reachability (hospital LAN/VPN). Escalated to whoever owns/
  administers the internal telephony server. **Answer confirmed
  (2026-08-26):** no additional credential is required or expected, and
  there is no reverse proxy in front of the endpoint enforcing anything
  beyond TLS — network segmentation (hospital LAN/VPN reachability) is the
  intended authentication boundary. Recorded in `docs/DECISIONS.md` D-059.
  The answer does not reveal a gap, so no `DocBot.ahk` implementation task
  follows from it; no speculative auth code was added.

### Acceptance evidence

Confirmed by the project owner on a compiled test build on the managed
Windows workplace / internal hospital network (2026-08-17).

- [x] Exploratory HTTPS test: registration/link code received.
- [x] Exploratory HTTPS test: test call successfully established.
- [x] Registration/link-code request succeeds in a compiled test build on a
  representative managed Windows workstation.
- [x] Event polling remains active over time, does not overlap, and recovers
  after the known stop/restart scenarios through HTTPS.
- [x] Linking and a controlled call to a designated test number succeed.
- [x] Certificate-name, trust-chain, expiry, and TLS failures are rejected and
  produce a clear, non-sensitive diagnostic instead of falling back to HTTP.
- [x] A telephony or SMS URL using `http://` is rejected during configuration
  validation with a clear, non-sensitive error. Implemented (D-043) and now
  confirmed on a compiled build on managed Windows, per the project's
  manual-validation reality (`docs/ARCHITECTURE.md` §19).
- [x] The final release/preflight checklist records the HTTPS base URL and
  certificate validation result without recording the confidential hostname,
  endpoints, telephone numbers, or certificate private material in Git.

This P1 entry is now fully resolved. The last open item, the "Application
and documentation" server-authentication confirmation, was answered by the
project owner (2026-08-26, see `docs/DECISIONS.md` D-059): no additional
credential is required and there is no reverse proxy in front of the
telephony endpoint. The project owner removed the separate "Infrastructure
dependencies" checklist (certificate ownership, reverse-proxy timeouts,
disabling the HTTP listener) as no longer tracked here.

This is a real `DocBot.ahk` behavior change. Implement it on a dedicated
feature/fix branch from the then-current `develop`, update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`, and validate the
compiled result on Windows and the internal network before integration.

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

- [x] The workflow now exists on both `main` (reached via the 2.2 release
  merge) and `develop` (brought back in the same step), so it protects all
  new work, not only the release line it started on.
- [x] Decided (2026-08-15, see `docs/DECISIONS.md` D-042): the
  `pull_request` trigger stays unscoped (any base branch) — every `.ahk`
  change must be syntax-checked, and old branches are not being reworked
  without consequence.
- [x] Decided (2026-08-15, see D-042): `workflow_dispatch` stays — it is
  used to validate a feature/fix branch on GitHub before/without a PR,
  ahead of local Windows testing.

This TODO item is fully resolved; no further action needed unless the
decision above is revisited.

---

## P1 — Limit local standard diagnostics to seven days

Implement automatic cleanup of standard diagnostic log entries older than
seven days.

- [x] Remove entries older than seven days from both the active standard log
  and the rotated `.oud` log without relying only on file modification time.
  Implemented on `claude/diagnostics-retention` (`AppVersion
  2.3-diagnostiek-retentie.2`); see `docs/DECISIONS.md` D-044.
  `PruneExpiredDebugLogEntries()` parses each entry's own leading timestamp.
- [x] Preserve the existing redaction and approximately 2 MB size-rotation
  behavior. Unchanged; the new pruning runs independently of
  `FlushDebugLog()`'s size rotation.
- [x] Ensure malformed or legacy log lines and cleanup failures do not block
  application startup. Unparseable entries are left in place rather than
  guessed at; all pruning is wrapped in `try` and runs after, not inside,
  the existing startup log-init `try` block. A real compiled test build
  surfaced actual pre-"v2" legacy lines (undated, unredacted, from before
  commit `5f72613`/2026-08-07) still present in a shared `debug.log` — see
  the D-044 addendum. `PruneExpiredDebugLogFile()` now specifically
  recognizes and unconditionally expires that known legacy format.
- [x] Verify on managed Windows that recent entries remain available, expired
  entries are removed and extended-session logging keeps its separate
  lifecycle. Confirmed on a real compiled test build: the project owner
  reported the standard-log pruning behaves correctly (recent entries kept,
  the legacy-line gap above included).
- [x] Keep `README.md` and `docs/DATA_PROTECTION.md` synchronized with the
  implemented behavior.

This changes `DocBot.ahk` behavior. Implement it on a dedicated feature/fix
branch from the then-current `develop` and update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`.

---

## P1 — Remove temporary problem-report artifacts

Complete the lifecycle of the report directory and temporary files created
during problem reporting. (Report files are attached individually, not as a
ZIP — see DECISIONS.md.)

- [x] On cancellation, remove the report directory and temporary extended log
  created for that report session. The extended log was already handled
  (`DeleteProblemReportExtendedLog()`/`ShutdownProblemReportLogging()`) for
  the *current* session; a real test build surfaced that an extended-log
  file orphaned by a crash/force-kill/Windows restart had no cleanup path
  at all (no session left to know its path). `PruneAbandonedExtendedLogFiles()`
  now sweeps `%LocalAppData%\DocBot\problem-report-*.log` older than seven
  days on the same daily timer as everything else below. The report
  *directory* only ever gets created as part of finalize (no separate
  synchronous "cancel after creation" UI point exists), so that remains
  covered by the abandoned-directory sweep below plus the two explicit
  paths. Implemented on `claude/diagnostics-retention`
  (`AppVersion 2.3-diagnostiek-retentie.3`); see `docs/DECISIONS.md` D-044
  and its addenda.
- [x] After successful attachment to an Outlook draft, remove the local
  report directory only after verifying that Outlook has safely taken over
  the attachments. `OpenProblemReportEmail()` now checks
  `mail.Attachments.Count = files.Length` and deletes the directory only
  after `mail.Display()` succeeds.
- [x] For the manual fallback, keep the report directory available until the
  user has had a usable opportunity to attach the files, then provide an
  explicit completion/cleanup path and a safe cleanup fallback for abandoned
  artifacts. `OpenProblemReportFallback()` now asks explicitly (default
  "No"); `PruneAbandonedProblemReportDirs()` sweeps any
  `DocBot_diagnose_*` directory older than seven days on the same daily
  timer as the log retention above, using the timestamp DocBot itself
  encodes in the directory name. Its naming regex now also accepts the
  older, pre-`2a8127e` (2026-08-08) directory name without the millisecond
  suffix, confirmed still present on a real test machine (see
  `docs/DECISIONS.md` D-044 addendum 2).
- [x] Verify that cancelling at each stage and closing DocBot cannot leave
  sensitive report artifacts behind indefinitely. Confirmed on a real
  compiled test build (`AppVersion 2.3-diagnostiek-retentie.6`): after
  fixing the pre-`2a8127e` naming-format gap and making the sweep summary
  log unconditionally (not only when something was found — see
  `docs/DECISIONS.md` D-044 addendum 3), the project owner confirmed both
  the "Probleemrapportmap opschonen" log line appears and the old
  directories are genuinely gone from disk. The unconditional logging is
  kept permanently, on project-owner request, as ongoing observable proof
  the seven-day cleanup runs — not only a debugging aid.
- [x] Update `README.md` and `docs/DATA_PROTECTION.md` to the implemented
  lifecycle.

This changes `DocBot.ahk` behavior. Implement it on a dedicated feature/fix
branch from the then-current `develop` and update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`.

---

## P1 — Standardize the local engineering workflow (done)

The project has suffered from GitHub connector limitations on the very large `DocBot.ahk` file and temporary GitHub Actions workflows used as an editing workaround.

Preferred workflow, now documented as the "Lokale werkwijze" subsection under
"Branch-workflow" in both `AGENTS.md` and `CLAUDE.md`:

- [x] local clone for source editing;
- [x] `git fetch --prune` before branch work;
- [x] branch from current `develop` unless explicit hotfix;
- [x] inspect `git status` before pull/switch;
- [x] commit or stash intentional local changes before `git pull`;
- [x] explicit per-commit preflight for AppVersion/README/telemetry docs;
- [x] push branch normally;
- [x] use GitHub PRs for review/integration;
- [x] perform Windows AHK functional validation separately when developing from a Mac.

Avoid workflow-as-editor/temporary trigger PRs unless normal git/connector
methods are genuinely unavailable — also now documented in the same
subsection, cross-referencing `docs/DECISIONS.md` D-036 and D-037.

This item documents the practice rather than changing `DocBot.ahk`, so no
`AppVersion` bump applies.

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

## P1 — Run `--selftest` automatically when compiling, with results visible on the console

Filed by the project owner (2026-08-25). Right now, confirming
`tests/SelfTests.ahk` passes against a compiled build is a manual step: run
`DocBot.exe --selftest` yourself, then go check
`%TEMP%\docbot-selftest-results.txt` and/or the process exit code, because
the console typically shows **no output at all** — `AutoHotkey64.exe`/
`DocBot.exe` are GUI-subsystem executables, and whether `FileAppend(text,
"*")` actually reaches a redirected stdout is unconfirmed in this codebase
(`docs/DECISIONS.md` D-053, `tests/README.md`). This was reconfirmed during
the 2.3 release: a compiled `--selftest` run produced empty console output,
and only the results file made the outcome ("32 tests, 32 geslaagd, 0
mislukt") actually visible.

Goal: make `Build-EPD_Machine.bat` run the self-test itself, right after
compiling `DocBot.exe` (`Build-EPD_Machine.bat` around the `Ahk2Exe`
call/errorlevel check, before `:deploy` is called for any target — see
`echo DocBot compileren naar DocBot.exe...`), and have the batch itself
print the actual test results to the command prompt so a developer running
the build sees them without a separate manual step.

### Scope

- [x] After a successful compile, run `"%OUTPUT%" --selftest` (the
  just-built `DocBot.exe`, not the interpreted script) and wait for it to
  exit — reuse the same `WaitForExit`/force-kill-style caution already
  applied in `.github/workflows/ahk-syntax-check.yml` for a GUI-subsystem
  AutoHotkey process that could otherwise show a blocking dialog instead of
  exiting cleanly (`docs/DECISIONS.md` D-040). Implemented via a new
  `tools/Invoke-WithTimeout.ps1` helper (kept out of the repository root
  per project-owner request) invoked from `Build-EPD_Machine.bat`; it
  applies the same `Start-Process -PassThru` / `WaitForExit(60000)` /
  `Stop-Process -Force` pattern as the CI step and passes the child's exit
  code through. Batch itself cannot do this directly: `cmd.exe` does not
  wait synchronously on a GUI-subsystem executable the way it does on a
  console executable, so a bare invocation would neither block correctly
  nor allow a timeout/kill. **Deliberately left the CI workflow's own
  inline `pwsh` fragment untouched** (project-owner decision) rather than
  switching it to the same helper in this change.
  **Windows validation surfaced a real problem (2026-08-26):** the initial
  version invoked the helper with `powershell -ExecutionPolicy Bypass -File
  tools\Invoke-WithTimeout.ps1 ...`, which failed on the project owner's
  managed workstation — Windows refused to load the unsigned `.ps1` file
  ("is not digitally signed") and ignored `-ExecutionPolicy Bypass`,
  because a Group Policy-configured execution policy always overrides that
  startup argument. Fixed by piping the script's content into
  `powershell -Command -` via stdin instead of `-File` (a command-text
  invocation is not subject to the script-file execution-policy check at
  all), with inputs passed via `INVOKE_WITH_TIMEOUT_*` environment
  variables instead of a `param()` block, since stdin-delivered content
  isn't bound to one. Recorded in `docs/DECISIONS.md` D-060.
  **A second Windows run (2026-08-26) confirmed the stdin fix itself
  worked** (the zelftest ran and printed "32 test(s), 32 geslaagd, 0
  mislukt" correctly), but then hit a second, unrelated bug: `cmd.exe`
  reported `"was unexpected at this time."` right after. Cause: the
  literal, unescaped `(pen)` in `echo Er is niets uitgerold naar de
  doelmap(pen).` inside the `if not "%SELFTEST_RESULT%"=="0" ( ... )`
  block — `cmd.exe` parses an entire `if (...)` block for balanced
  parentheses before deciding whether to run it, including parentheses
  inside plain `echo` text, so an unescaped `(`/`)` there breaks parsing
  regardless of whether the branch actually executes. Fixed by rewording
  to "Er is niets uitgerold naar de doelmap of doelmappen." (no
  parentheses) rather than escaping them, since the other message in the
  same block already needed `^(`/`^)` escaping for a literal exit-code
  parenthetical.
  **A third Windows run (2026-08-26) confirmed the selftest step itself
  now runs correctly end to end** (pass path, including the parenthesis
  fix), but surfaced a third, pre-existing bug unrelated to this TODO's
  own scope: the project owner answered "nee" to all three interactive
  questions, including "Ook een executable naar de naastgelegen map
  EPD_Machine kopieren?", but the batch copied to `EPD_Machine` anyway.
  Root cause: `:ask` (`Build-EPD_Machine.bat`) always writes the literal
  string `"J"` or `"N"` into its output variable, never leaves it empty,
  but the two downstream gates for `DO_EPD_COPY`
  (the `OVERWRITE_EPD_PACKAGES` question and the `EPD_Machine.exe` deploy
  itself) used `if defined DO_EPD_COPY`, which is true for *any* assigned
  value including `"N"` — so once the first question was asked at all,
  both were treated as "yes" regardless of the actual answer. Fixed by
  changing both checks to `if /I "%DO_EPD_COPY%"=="J"`. This bug predates
  this TODO entry's own changes (it sits in code this change never
  touched) and was only found because this task's Windows validation
  exercised the full interactive flow; not release-blocking by itself
  (declining the question was simply not honored, it didn't silently
  corrupt anything), but a real deploy-safety defect worth having fixed
  regardless. **Still needs a fourth Windows run to confirm declining all
  three questions now genuinely skips the `EPD_Machine` copy.**
  **A cosmetic issue was also reported (2026-08-26):** the console showed
  garbled characters (BOM mojibake, e.g. "ï»¿"-style glyphs) right before
  "ok" on the very first results line only; the 32/32 pass count itself
  was always correct. Cause: `tests/SelfTests.ahk`'s
  `FileAppend(logText, logPath, "UTF-8")` writes a UTF-8 byte-order mark
  at the start of the freshly created results file, and `type` renders
  that BOM as mojibake on a console whose active code page isn't UTF-8 —
  only visible on the first line because a BOM appears exactly once, at
  the very start of the file. Fixed by switching to `"UTF-8-RAW"`,
  matching the no-BOM convention `DocBot.ahk` already uses elsewhere for
  files that get read back (e.g. the JSON writers). Since this changes
  `tests/SelfTests.ahk`, which is `#Include`d into `DocBot.ahk` and
  affects the compiled build's `--selftest` output, `AppVersion` was
  bumped in the same commit to `2.4-selftest-encoding.1` per the
  branch-specific counter rule, and a `### 2.4 — In ontwikkeling` README
  changelog section was opened (this is the first `DocBot.ahk`-affecting
  change since the 2.3 release).
- [x] Regardless of whether anything appeared on stdout, explicitly read
  back `%TEMP%\docbot-selftest-results.txt` and `type` (or `echo`) its
  contents to the console — this file, not stdout, is the reliable source
  per D-053/`tests/README.md`. Implemented: the batch deletes any stale
  results file before running, then `type`s it after, regardless of the
  measured exit code.
- [x] Use the process exit code (`0` = all tests passed, `1` = a failure or
  unexpected error) as the authoritative pass/fail signal, matching how the
  CI step already treats it. Decide and document explicitly what the batch
  then does on a nonzero exit code — e.g. print a clear failure banner and
  `goto :failed` before any `:deploy` call, so a broken build is never
  rolled out to a target folder. Do not silently continue on failure.
  Implemented: `SELFTEST_RESULT` is captured immediately after the
  PowerShell call and checked explicitly; a nonzero value (including a
  timeout/force-kill) prints a failure banner and jumps to `:failed` before
  either `:deploy` call.
- [x] Keep this self-test run local to the source build step; it must not
  run against an already-deployed target copy of `DocBot.exe`, and must not
  block or alter the existing interactive question-answering flow
  (`docs/DECISIONS.md` D-052 and the pre-asked-questions change in the 2.3
  changelog) — it runs after all questions are answered, alongside the
  compile step itself. Implemented: it runs against `%OUTPUT%` (the
  freshly compiled source-tree executable) only, placed right after the
  compile step and before the first `call :deploy`, after all interactive
  questions have already been asked.
- [x] Handle a missing/unreadable results file the same way the CI step
  does: warn clearly instead of crashing the batch, and still rely on the
  exit code for pass/fail. Implemented with the same `if exist ... (type
  ...) else (echo Waarschuwing: ...)` shape as the rest of the batch.
- [x] Update `tests/README.md` and the `Build-EPD_Machine.bat` section of
  `README.md` to document that a compile now also runs and displays the
  self-test results, so this isn't a surprise the next time someone reads
  either doc. Done in the same change.

This changes `Build-EPD_Machine.bat`, not `DocBot.ahk` — no `AppVersion`
bump applies (`--selftest` already exists and works; this only invokes it
automatically and surfaces its existing output). Implemented on
`claude/next-5-todo-tasks-h6kn5k`; **not yet functionally validated on
Windows** (git-only editing environment, per `docs/DECISIONS.md` D-037) —
needs a real compile run to confirm the PowerShell helper actually
times out/force-kills a hung `--selftest` and that a genuine test failure
is surfaced and blocks deployment as designed.

---

## P1 — Also offer the EPD_Machine copy question for a stable release, not only `-dev`/`-rc`

Filed by the project owner (2026-08-25). `Build-EPD_Machine.bat` only asks
"Ook een executable naar de naastgelegen map EPD_Machine kopieren?" when
`IS_DEVELOP` is set — and `IS_DEVELOP` is only set when `global AppVersion`
in the source contains `-dev` or `-rc`:

```bat
rem Alleen de centrale developversie of een RC mag vanaf een directe submap
rem van DocBot optioneel ook naar de naastgelegen applicatiemap EPD_Machine
rem worden uitgerold.
set "IS_DEVELOP="
findstr /B /C:"global AppVersion" "%SOURCE%" | findstr /C:"-dev" /C:"-rc" >nul
if not errorlevel 1 set "IS_DEVELOP=1"
```

A stable numeric `AppVersion` (e.g. `2.3`, no prerelease suffix) never
matches `-dev`/`-rc`, so `IS_DEVELOP` stays unset and the EPD_Machine
question — and therefore the whole `EPD_Machine.exe`/packages copy path
below it — is silently skipped when placing a stable release, even though
the co-located `EPD_Machine` folder may need the same update.

### Scope

- [ ] Extend the `IS_DEVELOP`-gated condition (or introduce a clearer,
  separate flag) so a stable numeric `AppVersion` also triggers the
  "Ook een executable naar de naastgelegen map EPD_Machine kopieren?"
  question, alongside the existing `-dev`/`-rc` case — not only when a
  development or release-candidate build is placed.
- [ ] Decide explicitly, and document the decision here and in a code
  comment: should this stay scoped to stable + `-dev`/`-rc` only (i.e.
  still exclude a feature/fix branch's own prerelease build, matching the
  existing rationale that only the central dev/RC line and now stable
  releases are expected to also update `EPD_Machine`), or should every
  `AppVersion` shape ask the question? Default assumption unless the
  project owner says otherwise: keep feature/fix branch builds excluded,
  only add stable to the existing `-dev`/`-rc` allowance.
- [ ] Re-check the variable name `IS_DEVELOP` once the condition covers
  stable releases too — it will no longer mean "is a development build",
  so keep or rename it deliberately rather than leaving a now-misleading
  name.
- [ ] Verify the rest of the `DO_EPD_COPY` path (the `OVERWRITE_EPD_PACKAGES`
  question and the `:deploy` call for `EPD_Machine.exe`) already behaves
  correctly once triggered from a stable build — it should, since that path
  does not itself branch on `IS_DEVELOP` again, only on `DO_EPD_COPY`.
- [ ] Update the `Build-EPD_Machine.bat` description in `README.md` (and the
  code comment above `IS_DEVELOP`) so it no longer says only a "centrale
  developversie of een RC" gets this option.

This changes `Build-EPD_Machine.bat`, not `DocBot.ahk` — no `AppVersion`
bump applies.

---

## P2 — Remove the optional `itemCount` package-manifest check

Reported by the project owner (2026-08-25): the optional `itemCount` field
on a bundled package (checked in `LoadBundledPackageFile()`, `DocBot.ahk`
around line 6886) throws a loading error whenever it does not exactly match
`package["items"].Length`:

```
Pakket {id} vermeldt {itemCount} items, maar bevat er {items.Length}.
```

`items.Length` is already the authoritative count; `itemCount` is a
separately maintained manifest field that must be kept in sync by hand
whenever a package's item list changes on the network share. It adds no
value over just counting `items` and only creates a way for an otherwise
valid package to fail to load.

- [ ] Remove the `itemCount` consistency check (and, if nothing else reads
  the field, the `itemCount` field handling) from `LoadBundledPackageFile()`.
- [ ] Check whether `itemCount` is written/read anywhere else (package
  authoring tooling, other loaders, `docs/MIGRATIONS.md`) and remove those
  references too so nothing still expects it to be kept in sync.
- [ ] Update `docs/ARCHITECTURE.md`/`docs/MIGRATIONS.md` if they document
  `itemCount` as a required/validated package field.

This changes `DocBot.ahk` behavior. Implement it on a dedicated feature/fix
branch from the then-current `develop` and update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`.

---

## P2 — Change user-data profile selection to build mode (done)

**Status: implemented and fully validated** (`docs/DECISIONS.md` D-056,
supersedes D-009) on branch `claude/profielselectie-build-vorm-bdkt6j`. Both
remaining Windows-functional-validation rows (D-037) were confirmed by the
project owner on 2026-08-25; kept here as a record rather than removed.

_Downgraded from P1 to P2 on 2026-08-17: this closes a real gap in D-009's
data-isolation intent (an uncompiled `develop`/`-rc` script run currently
shares the central `DocBot-test` profile with real testers, and a compiled
feature/fix acceptance-test build lands in `DocBot-dev` instead), but no
concrete incident from either gap is recorded, and in the project's actual
workflow only the project owner compiles and tests builds — the
uncompiled-run scenario is expected to be rare in practice. Correctness/
future-proofing improvement, not release-blocking._

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

- [x] Change the profile-selection logic in `DocBot.ahk` (currently centered around `GetUserDataProfile(AppVersion)`) so it incorporates stability plus `A_IsCompiled`.
- [x] Keep the existing one-time bootstrap chain unless implementation review finds a concrete reason to change it: missing `DocBot-test` copies from `DocBot`; missing `DocBot-dev` prefers `DocBot-test`, otherwise `DocBot`; never overwrite an existing destination profile. (No reason found; `InitializeUserStorage()`/`GetUserDataSeedDirectory()` left unchanged — they already operate on the resulting profile name.)
- [x] Update nearby source comments so they no longer describe `-dev`/`-rc` versus other prerelease suffixes as the profile selector.
- [x] Update `README.md` wherever the old profile rule is described.
- [x] Update the `Gebruikersprofielen` rule in both `AGENTS.md` and `CLAUDE.md`; make explicit that build form, not feature/RC suffix, selects the non-stable profile.
- [x] Update `docs/PROJECT_CONTEXT.md` and `docs/ARCHITECTURE.md` to the new invariant/data-flow.
- [x] Add/supersede the corresponding storage-profile decision in `docs/DECISIONS.md` rather than silently erasing the old rationale. (D-056 supersedes D-009.)
- [x] Revisit this TODO and any acceptance-test wording that still assumes suffix-only profile selection.
- [x] Do not change the branch-version scheme (`2.3-dev.N`, `2.3-<branch>.N`, `2.3-rc.N`, stable `2.3`).
- [x] Do not treat package-cache behavior under `%LocalAppData%` as part of this change unless explicitly approved; this task concerns Documents/config/user-data profile selection.
- [x] Telemetry payload, fields and interval should remain unchanged; only its `settings.ini` location follows the selected user profile. Update telemetry documentation only if the implementation changes telemetric behavior beyond that.

### Required test matrix

The first eight rows are covered by pure-logic self-tests
(`TestGetUserDataProfile` in `tests/SelfTests.ahk`, run via
`DocBot.ahk --selftest`). The last two rows involved real file-system
bootstrap/migration and needed Windows functional validation (D-037);
confirmed by the project owner on 2026-08-25.

- [x] Stable `2.3`, compiled -> `Documents\DocBot`. (self-test)
- [x] Stable `2.3`, noncompiled -> `Documents\DocBot`. (self-test)
- [x] `2.3-dev.N`, compiled -> `Documents\DocBot-test`. (self-test)
- [x] `2.3-rc.N`, compiled -> `Documents\DocBot-test`. (self-test)
- [x] Feature/fix prerelease such as `2.3-example.1`, compiled -> `Documents\DocBot-test`. (self-test)
- [x] `2.3-dev.N`, noncompiled -> `Documents\DocBot-dev`. (self-test)
- [x] `2.3-rc.N`, noncompiled -> `Documents\DocBot-dev`. (self-test)
- [x] Feature/fix prerelease, noncompiled -> `Documents\DocBot-dev`. (self-test)
- [x] Existing `DocBot-test` and `DocBot-dev` directories are never repopulated/overwritten merely because selection rules changed. (validated on Windows, 2026-08-25)
- [x] Stored hotstring/settings/package/speeddial paths still migrate or resolve correctly in the selected profile. (validated on Windows, 2026-08-25)

### Version/preflight requirement when implementing

This is a real `DocBot.ahk` behavior change, so implement it on its own feature/fix branch from the then-current `develop`. Every commit that changes `DocBot.ahk` must update the branch-specific `AppVersion` in that same commit. README/changelog need must be assessed in the same commit sequence; telemetry documentation only changes if telemetry behavior/config/payload changes.

---

## P2 — Harden the standard-log format migration check beyond the first 256 bytes

Discovered 2026-08-17 (see `docs/DECISIONS.md` D-044) via a real
compiled test build: `debug.log` is not channel-specific
(`GetStandardDebugLogPath()` always returns
`%LocalAppData%\DocBot\debug.log`, regardless of stable/test/dev profile),
so every build ever run on a machine shares one file.
`InitializeDiagnosticLogging()` only reads the first 256 bytes at startup to
decide whether the file is current-format and needs wiping; once a valid
"DocBot standaardlog v2" header exists at the top, nothing re-validates the
rest of the file on later startups. If an older/rolled-back build is ever
run again against that same file, it can append its own (possibly
unredacted or otherwise non-conforming) format underneath an
already-valid-looking header, and no future startup notices.

The immediate symptom (pre-"v2" legacy lines from before commit `5f72613`
never expiring) is already fixed in `PruneExpiredDebugLogFile()`, which now
specifically recognizes that one known legacy format. This item is about
the more general root cause, for whatever future format mismatch isn't
already known/pattern-matched:

- [ ] Decide on an approach: e.g. validate every line's format (not just the
  header) during `InitializeDiagnosticLogging()`, or make
  `PruneExpiredDebugLogFile()`'s "does this line match a known format"
  check exhaustive (current format + every known legacy format) with
  unconditional expiry for anything that matches no known format at all,
  rather than the current conservative "keep unknown content" default.
- [ ] Weigh the tradeoff explicitly: the current conservative default
  favors not deleting recent-but-corrupted entries; a stricter default
  favors not indefinitely retaining unredacted content. Record the decision
  in `docs/DECISIONS.md`.
- [ ] If changed, keep it consistent with the "malformed/legacy content must
  not block startup" invariant from the seven-day-retention work.

This changes `DocBot.ahk` behavior. Implement it on a dedicated feature/fix
branch from the then-current `develop` and update the branch-specific
`AppVersion` in every commit that changes `DocBot.ahk`.

---

## P2 — Introduce targeted automated tests where practical

There is now a `tests/` directory, but only for what is practical without a
live hospital environment or a code module split (see `docs/DECISIONS.md`
D-053). High-value testable areas:

- [x] stable/non-stable + compiled/noncompiled -> user-profile selection.
  Covered by `TestGetUserDataProfile` (see the "P2 — Change user-data
  profile selection to build mode" entry above; this line was left
  unchecked here by oversight when that work landed).
- [x] telephone-number normalization. Covers `NormalizePhoneNumber()` (the
  clipboard-detection combination function), `NormalizePhoneNumberInternal()`/
  `NormalizePhoneNumberExternal()`, and `NormalizeSmsPhoneNumber()`:
  4-digit internal numbers, +31/0031/kaal-`0` external NL numbers with
  spaces/dashes ignored, the SMS-specific 06-only acceptance, and
  too-short/invalid input for each. Implemented on
  `claude/next-5-todo-tasks-h6kn5k` (`AppVersion 2.4-selftest-encoding.2`).
- [ ] hotstring execution-mode selection;
- [ ] dynamic token expansion;
- [x] JSON migration/default-addition idempotency. Implemented as
  `tests/SelfTests.ahk`, run via `DocBot.ahk --selftest` and wired into
  `.github/workflows/ahk-syntax-check.yml` as a second step. Covers
  `ReadSchemaVersion()`/`RejectNewerSchemaVersion()` and the idempotency of
  `AddMissingDefaultHotstrings()`/`AddMissingDefaultSpeedDials()`/
  `NormalizeHotstringItem()`. Does not cover the file I/O, `.bak`/temp-file
  write path, or GUI-refresh side of the four loaders — see
  `tests/README.md` for the exact boundary. Implemented on
  `claude/schema-migrations-setup-waiigd` (`AppVersion
  2.3-schema-migraties.1`); confirmed by the project owner on real Windows
  (interpreted `AutoHotkey64.exe DocBot.ahk --selftest`, 24/24 passing,
  2026-08-19, see `docs/DECISIONS.md` D-053). A compiled
  `DocBot.exe --selftest` run (2026-08-25) confirmed the same via
  `%TEMP%\docbot-selftest-results.txt`: "32 tests, 32 geslaagd, 0 mislukt"
  (the higher count reflects the D-056 profile-selection assertions added
  since the 24/24 run, not a discrepancy). Console output stayed empty in
  both cases, as expected for a GUI-subsystem executable per this same
  D-053 caveat.
- [ ] package conflict resolution and status calculation;
- [ ] telemetry payload serialization/redaction boundaries;
- [ ] telemetry InstallationId persistence state machine using controlled file conditions;
- [ ] parsing/validation of package manifest and package files.

Keep live telephony/Edge/UIA tests as integration/manual tests unless a realistic Windows harness is introduced.

---

## P2 — Make migration behavior easier to inspect (done)

There is no `migrations/` directory; migrations are embedded in `DocBot.ahk` and keyed by schema versions.

- [x] Document which schema version added which field/default, which old
  filenames/formats are still supported, and the shared
  `ReadSchemaVersion()`/`RejectNewerSchemaVersion()` helpers used by all
  four loaders: `docs/MIGRATIONS.md`, added on
  `claude/schema-migrations-setup-waiigd` (`AppVersion
  2.3-schema-migraties.1`; see `docs/DECISIONS.md` D-053).
- [ ] "Which migrations are safe to remove only after a defined
  compatibility window" is not yet answered — `docs/MIGRATIONS.md` records
  current behavior, not a removal/deprecation policy. Revisit if a schema
  ever needs an old migration branch retired.

Migration code itself was deliberately **not** moved to a separate file for
this change — see the rejected alternative in D-053. Do not move it later
just for cleanliness; only as part of the broader, non-casual modularization
already tracked below ("Consider gradual modularization after 2.2").

---

## P2 — Add a user instruction for safe hotstring content (done)

Create and maintain an end-user instruction for personal hotstrings. The
instruction must:

- [x] explain that hotstrings are intended for generic, reusable text;
- [x] prohibit patient-identifying and patient-specific content in
  `hotstrings.json`;
- [x] distinguish prohibited patient-specific content from generic clinical
  formulations that are not linked to an identifiable patient;
- [x] explain that a name, telephone number, e-mail address or signature of
  the employee can be personal data and remains subject to organizational
  policy;
- [x] explain that DocBot cannot technically determine whether free text
  contains patient-specific information;
- [x] identify where the instruction is presented to users and who owns its
  review and maintenance. Presented as a fifth Help accordion section plus
  an always-visible hint on the Tekstvervanging page, and summarized in
  `README.md`; owned by the project owner.

Implemented on `claude/hotstring-user-instruction-hcv2jw`
(`AppVersion 2.3-hotstring-instructie.6`); see `docs/DECISIONS.md` D-045.
Aligned with `docs/DATA_PROTECTION.md` §3.4 (updated in the same change) and
`README.md`. Per project-owner decision, this does not (yet) extend to
organizational onboarding — the in-product instruction is intended to cover
that on its own.

- [x] Validate on a compiled build on a managed Windows workstation: the new
  Help section (including that a fifth accordion section still fits above
  the "Probleem melden..." button), the always-visible hint on
  Tekstvervanging in both the compact and expanded editor state, and that
  the Hotstrings/Telefonie/Over cards now end at a consistent y=648 without
  visual overlap or clipping. Confirmed good by the project owner,
  2026-08-25.

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
