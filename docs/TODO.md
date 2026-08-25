# DocBot — TODO

_Last updated: 2026-08-25. This file is a handover backlog, not a promise that every lower-priority idea must be implemented. Re-check repository/PR state before acting._

## Priority legend

- **P0** — blocks the current release path or risks a broken build.
- **P1** — should be completed before/around the current release or immediately afterwards.
- **P2** — valuable engineering improvement; not a reason to destabilize the current release.

---

## P0 — Release plan: finalize stable DocBot 2.3

### Current status (checked 2026-08-25)

- `develop` is at `AppVersion = 2.3-dev.9` and has not advanced since
  `release/2.3-rc` was cut from it; every commit on `develop` is also on
  `release/2.3-rc`, but not the reverse.
- `release/2.3-rc` (origin, no open PR yet against `main`) is at
  `AppVersion = 2.3-rc.3` and carries RC-only fixes not yet merged back to
  `develop`: the CRLF line-ending fix for `Build-EPD_Machine.bat`
  (`docs/DECISIONS.md` D-057), removal of the best-effort `attrib`-based
  user-data-folder pin (D-058), `Build-EPD_Machine.bat` asking all its
  interactive questions up front, and accompanying `packages/anest.json`
  updates.
- The README `### 2.3 — In ontwikkeling` changelog section on
  `release/2.3-rc` already lists the full feature/fix set for this release
  (profile selection by build form, HTTPS-only telephony/SMS, SMS default
  text, package share-dir change, diagnostics/report-artifact retention,
  the hotstring-content Help instruction, `tests/SelfTests.ahk` plus
  `DocBot.ahk --selftest`, and the two RC-only fixes above). Treat that
  section, not this file, as the authoritative feature list for the
  release notes.
- No stable-release work (`AppVersion 2.3`, README finalization, tag) has
  happened yet. This section is the plan for getting there; it does not by
  itself perform any of the steps.

### Remaining blockers before merging `release/2.3-rc` into `main`

- [x] "P1 — Baseline debug output for repeated SMS window/tab reopening"
  (below): the project owner attempted to reproduce the reopening issue on
  a real compiled build and could not trigger it. The baseline logging that
  would capture the decision path if/when it does recur is in place and
  ships as-is. **Decision: does not block the release** — the remaining
  "Investigate" line becomes a known follow-up, only actionable if/when the
  issue actually recurs in the field with the new logging active.
- [ ] `tests/SelfTests.ahk` (24/24) confirmed via an interpreted
  `AutoHotkey64.exe DocBot.ahk --selftest` run. A compiled
  `DocBot.exe --selftest` run produced **no visible output** — before
  treating this as a pass or a bug, check the two outputs the code itself
  treats as authoritative rather than the console: the process exit code
  (`0` = all tests passed, `1` = at least one failure/error) and
  `%TEMP%\docbot-selftest-results.txt` (overwritten on every run). Absence
  of console text is expected and already documented as unconfirmed
  behavior for a GUI-subsystem executable (`docs/DECISIONS.md` D-053,
  `tests/README.md`) — it is not itself a failure signal. Still open until
  the exit code and/or results file are actually checked and recorded.
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

Only the compiled `--selftest` exit-code/results-file check remains open in
this list.

### Acceptance checklist for what changed since 2.2

Run this in addition to, not instead of, the full 2.2 RC3 regression
checklist above — that checklist still covers unchanged behavior end to
end.

- [ ] Compiled build reads its `packages` folder from next to the
  executable (`A_ScriptDir`) on the correct network share; a local-copy
  launch (e.g. via Ivanti) still honors `LocalConfig["Packages"]["ShareDir"]`
  as an explicit override (D-048/D-049).
- [ ] Package manifest entries with only `id`/`file` still load correctly;
  an optional package `owner` field displays next to the package name in
  **Pakketten** (D-054).
- [ ] Closing the package manager while conflict status for a large package
  is still being calculated no longer errors (D-051).
- [ ] `Build-EPD_Machine.bat` populates a `packages` folder next to every
  deployed executable, asking before overwriting an existing one (D-052);
  it asks all interactive questions before compilation starts, where Enter
  means "Ja" and only an explicit "N" means "Nee"; and it runs correctly
  from a fresh checkout now that `.gitattributes` forces CRLF (D-057).
- [x] Non-stable installs pick `DocBot-test` when compiled and `DocBot-dev`
  when run from source, regardless of the `-dev`/`-rc`/feature-name
  prerelease label (D-056) — validated on Windows. `DocBot.ahk --selftest`
  passed interpreted (24/24); the compiled `DocBot.exe --selftest` run
  still needs its exit code / `%TEMP%\docbot-selftest-results.txt` checked
  (see blocker above) before this line is fully closed.
- [ ] Telephony `BaseUrl` and every `SmsCallAction.Url` are rejected at
  startup when not `https://` (D-043) — re-confirm once more on the final
  RC build.
- [ ] An SMS page configured with `TextFieldId` offers a per-page multiline
  default text under **Instellingen > SMS actie** (hard enters preserved)
  that is filled into the message field after the phone number (D-055).
- [x] The standard log/live debug window now shows, without an active
  extended-logging session, which SMS window/tab path was attempted and
  why (`RunSmsCallAction()` and friends). Confirmed present; the actual
  reopening issue itself was not reproducible on a real compiled build
  (see "P1 — Baseline debug output..." below).
- [ ] Standard log entries older than seven days (including legacy
  pre-"v2" lines) are pruned from both the active log and `.oud`; the
  ~2 MB size-rotation behavior is unaffected (D-044).
- [ ] Abandoned problem-report directories/extended logs older than seven
  days are cleaned up automatically, with the "Probleemrapportmap
  opschonen" log line appearing even when nothing was found; cancel/
  Outlook/manual-fallback cleanup behaves as documented.
- [ ] DocBot starts without triggering an application-whitelisting security
  dialog on a hardened workstation now that the `attrib`-based folder pin
  is removed entirely (D-058).
- [ ] `docs/MIGRATIONS.md` still matches actual schema-version behavior for
  all four loaders.

### Finalizing the stable release (per the branch/version rules in `CLAUDE.md`/`AGENTS.md`)

- [ ] On `release/2.3-rc`, set `global AppVersion` from the final
  `2.3-rc.N` to stable `2.3` in the definitive release commit (this changes
  `DocBot.ahk`, so the AppVersion rule applies; branch type = release
  branch).
- [ ] Update README status wording from release-candidate/"in ontwikkeling"
  to stable 2.3 wording.
- [ ] Finalize `### 2.3` in the README Changelog (drop "— In ontwikkeling");
  it remains the only maintained version-history source — do not hand-edit
  `BuildAboutText()`.
- [ ] Verify the README `Telemetrie` section still exactly matches the
  shipped payload and interval (no payload change is currently planned for
  2.3 — confirm nothing slipped in unreviewed).
- [ ] Verify license/documentation references (PolyForm Noncommercial plus
  the ThirdParty MIT notices) are still accurate.
- [ ] Open a pull request from `release/2.3-rc` into `main`; merge with
  **Create a merge commit**, and only after the project owner has explicitly
  reviewed and approved the RC.
- [ ] After merging, create the annotated tag `v2.3` on the stable release
  commit — this needs its own explicit go-ahead from the project owner
  first, separate from approval of the merge itself (per `CLAUDE.md`,
  §"Verantwoording bij versie- en tagwijzigingen"); do not treat tagging as
  implied by release approval.
- [ ] Push the tag to `origin` and confirm it is visible there before
  treating it as done.
- [ ] Bring the release-only fixes back into `develop` via their own pull
  request/merge commit (mirrors PR #28 for 2.2).
- [ ] Start the next development version on `develop`
  (`AppVersion = 2.4-dev.1`) once the merge-back above lands.
- [ ] Delete the temporary release branch(es) after merging, once their
  content lives on in `main`/`develop` history and tag `v2.3`.
- [ ] Update `docs/PROJECT_CONTEXT.md` §3 (branch/release status) and mark
  the corresponding items resolved in this file, in the same change.

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

## P1 — Make HTTPS mandatory for telephony and SMS URLs

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
- [ ] This is an infrastructure/organizational question, not a DocBot code
  task, and not something resolvable from within this repository or by the
  project owner alone: DocBot's own requests (`IPT_callNumber()`,
  `IPT_register()`) send no application-level credential today — no API
  key, bearer token, or client certificate, only an `Accept-Language`
  header — so as far as the code shows, the only current "authentication"
  is network reachability (hospital LAN/VPN). Escalate to whoever owns/
  administers the internal telephony server (or the hospital network/
  security team) and ask explicitly:
  - Is the endpoint reachable only from within the hospital network/VPN,
    i.e. is network segmentation the intended authentication boundary?
  - Does the server expect an additional credential (API key, token,
    client certificate/mTLS) that DocBot does not currently send?
  - Is there a reverse proxy in front of it enforcing anything beyond TLS?
  Record the answer in `docs/DECISIONS.md` once known. Only if the answer
  reveals a real gap does this become a scoped `DocBot.ahk` implementation
  task (e.g. sending a configured credential header); until then, do not
  add speculative auth code with no confirmed server-side contract.

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

The only remaining open item in this P1 entry is the "Application and
documentation" server-authentication confirmation above. The project owner
removed the separate "Infrastructure dependencies" checklist (certificate
ownership, reverse-proxy timeouts, disabling the HTTP listener) as no
longer tracked here.

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

- [ ] stable/non-stable + compiled/noncompiled -> user-profile selection;
- [ ] telephone-number normalization;
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
  2026-08-19, see `docs/DECISIONS.md` D-053). Still open: a compiled
  `DocBot.exe --selftest` run (2026-08-25) showed no visible console
  output — expected per this same D-053 caveat for a GUI-subsystem
  executable, not itself a failure signal — but the process exit code and
  `%TEMP%\docbot-selftest-results.txt` (the two outputs the code treats as
  authoritative) have not yet been checked against the compiled build. This
  line stays open until one of those two is actually read and recorded.
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
