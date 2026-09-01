# DocBot — TODO

_Last updated: 2026-08-31. This file is a handover backlog, not a promise that every lower-priority idea must be implemented. Re-check repository/PR state before acting._

## Priority legend

- **P0** — blocks the current release path or risks a broken build.
- **P1** — should be completed before/around the current release or immediately afterwards.
- **P2** — valuable engineering improvement; not a reason to destabilize the current release.
- **P3** — low-priority polish; correct as filed, but narrow-impact or
  cosmetic enough that it can sit indefinitely without hurting the
  project. Pick up opportunistically, not on a schedule.

---

## P0 — Autostart race: user-data storage not yet available at DocBot startup (implemented and merged into `develop`; not yet in a stable release)

Filed 2026-08-28 from a user-supplied standard log
(`docs/uploads/0dbac3d9-standaardlog.txt`, redacted). DocBot was started via
autostart at Windows logon; within the same ~0.1s window right after the
bundled packages finished loading, four separate `Opslagfout` entries were
logged in immediate succession:

1. `Het JSON-bestand kon niet worden geladen.` — personal hotstrings
   (`InitializeHotstringStorage()` / `LoadHotstringsFromJson()`).
2. `De pakketkeuzes konden niet worden geladen. Standaard worden geen
   pakketten geactiveerd.` — package selections
   (`InitializePackageSettings()` / `LoadPackageSettingsFromJson()`).
3. `Het JSON-bestand kon niet worden geladen.` — speed dial
   (`InitializeSpeedDialStorage()`).
4. `Het JSON-bestand kon niet worden geladen.` — SMS default texts
   (`InitializeSmsDefaultTextStorage()`).

All four report the same underlying Windows error, "Het systeem kan geen
toegang verkrijgen tot het bestand" (access denied) — consistent with the
Documents/OneDrive-backed user-data folder not being fully available yet at
the moment autostart fires. One minute later, `Telemetry_TryEnsureInstallationId()`
also failed to persist a new installation ID (`✕ Telemetrie — Installatie-ID
kon niet worden opgeslagen`), retried again a minute after that (per its
documented quick-retry cadence, D-027/D-028), and DocBot ran for roughly
nine minutes with no packages active. A manual restart ~9 minutes later
loaded every store cleanly on the first attempt, confirming this is a
startup-timing race against storage availability, not a persistent storage
problem.

### Root cause

`Telemetry_TryEnsureInstallationId()` is the *only* startup loader with a
retry path (quick retries every `TelemetryInstallationIdQuickRetryMs`, then
hourly — D-027/D-028). Every other startup loader called from the
auto-execute section (`LoadAppSettings()`, `InitializeHotstringStorage()`,
`InitializePackageSettings()`, `InitializeSpeedDialStorage()`,
`InitializeSmsDefaultTextStorage()`) attempts exactly once, and on failure
falls back to in-memory defaults/empty state for the rest of that running
session — with no retry and no path back to the real stored data until the
next full restart:

- `LoadAppSettings()` (`settings.ini`) is the most silent case: it starts
  with `if !FileExist(ConfigFile): return`, so if the same transient
  access-denied condition makes `ConfigFile` appear not to exist yet, the
  function returns with **no log line at all** — `State["AutoSave"]`,
  `State["CallAction"]`, `State["SmsCallActionTitle"]` and
  `State["TextReplacement"]` silently keep their code defaults for the
  session, indistinguishable in the log from a genuine first run.
- `Telemetry_ReadCounter()` (used for `PhoneActions`, `LongHotstringActions`,
  `SmsActions`) reads once via `IniRead` wrapped in a bare `try`/`catch` that
  returns `0` on any failure. If this same race zeroes the in-memory
  counters for a session, a later `Telemetry_WriteCounter()` call during
  that same run would persist the artificially-low count over the real
  cumulative value — turning a transient read failure into a permanent loss
  of usage history, not merely a delayed one.
- The four JSON loaders above each log a single `Opslagfout` and then run
  the rest of the session on defaults/empty data (no packages active,
  personal hotstrings/speed dial/SMS default texts unavailable) with no
  further attempt to reload once storage becomes available again.

### Open question: telling "not yet available" apart from a genuine first run

`InitializeUserStorage()` treats `!DirExist(UserDataDir)` as "first run" and
immediately bootstraps (copies from a seed profile, or creates a fresh
directory) — a single, synchronous, one-shot check that runs before any of
the loaders above. This is a different, harder ambiguity than the four
loader failures: a JSON loader failing with "kon niet worden geladen" (not
"bestaat niet") already proves the file exists but is temporarily
unreadable — that case is unambiguous and safe to retry as proposed below.
But `DirExist(UserDataDir) = false` looks identical whether (a) the user has
genuinely never run DocBot, or (b) OneDrive has not mounted far enough yet
for even the folder structure/placeholders to be visible. Nothing in a
single snapshot can tell these apart.

Proposed resolution: do not try to classify intent from one passive
measurement. Instead, actively probe writability, and let the probe double
as the real bootstrap once it proves safe (suggested by the project owner):

1. If the file can't be read: check whether it exists. If not, check
   whether the folder exists. If neither exists, attempt to create a
   uniquely-named temporary folder under `A_MyDocuments` (a real
   `DirCreate`, not just a `DirExist` poll) — a write attempt is a strictly
   stronger signal than re-polling `DirExist`, since a not-yet-mounted
   OneDrive should fail an actual write, not just look empty.
2. Once that temporary folder can be created, re-check whether `UserDataDir`
   and the settings file are readable *now*:
   - Yes → the real profile surfaced while the probe was running (pure
     OneDrive-lag case); delete the temporary folder and proceed on the
     real data. No bootstrap, no risk of treating an existing user as new.
   - No → the temporary folder's successful creation just empirically
     proved this location is writable and `UserDataDir` genuinely does not
     exist — a high-confidence first run. Rename the temporary folder into
     place as `UserDataDir` (reusing it rather than creating a second
     folder) and bootstrap settings there as today.
3. Retry the whole probe on the same bounded cadence as the other loaders
   if the `DirCreate` itself fails — that failure is the "storage backend
   not ready" signal and should log as such (distinct from a first-run
   message).

Two existing patterns in the codebase apply directly here and should be
reused rather than re-invented:

- **Multi-instance race on the rename step.** If autostart fires twice, or
  a user launches DocBot manually while an autostart instance is still
  probing, two instances could each create their own temporary folder and
  both attempt to claim `UserDataDir`. `Telemetry_TryEnsureInstallationId()`
  already solves the equivalent race for the installation ID by re-reading
  immediately before use and letting an existing value win. Apply the same
  rule here: immediately before renaming, re-check whether `UserDataDir`
  now exists; if it does, discard the own temporary folder and use the
  existing one instead of renaming over it.
- **Cleanup of an orphaned probe folder.** If DocBot exits (crash, forced
  kill, Windows restart) between creating the temporary folder and
  renaming/deleting it, a stray folder is left in the user's Documents.
  `PruneAbandonedProblemReportDirs()` (P1 "Remove temporary problem-report
  artifacts") already sweeps a recognizable naming pattern older than seven
  days on the existing daily cleanup timer — give the probe folder a
  similarly recognizable name and fold it into that same sweep rather than
  adding a new cleanup mechanism.

**This must run asynchronously, after the GUI is already shown — not in the
current synchronous auto-execute sequence.** `InitializeUserStorage()` is
called before `BuildMainGui()`/`MainGui.Show()` today; if the probe/retry
loop (or the earlier plain bounded-retry idea) stays there as written, a
multi-minute retry window would delay the main window from appearing at
all, which is exactly the blocking startup gate D-026 already rejected —
only now scoped to one decision instead of everything. The probe must move
to the same asynchronous, timer-driven shape the telemetry installation ID
already uses: the GUI shows immediately on whatever data is available
(exactly as it does today), and the probe/rename logic runs on the
background retry timer afterward, refreshing the relevant in-memory
state/GUI once it resolves either way.

**Considered and dropped: a `DirExist(A_MyDocuments)` first gate.** An
earlier draft of this proposal added a cheap pre-check on the Documents
root itself, to let a high-confidence first run (existing OneDrive user,
first DocBot launch) bootstrap immediately instead of waiting out the full
retry window. Dropped (project-owner decision, 2026-08-28): it was a speed
optimization only, never part of the actual safety net — the write-probe
above is already correct and safe on its own regardless of whether this
organization's Documents folder is itself OneDrive-redirected (Known
Folder Move) or a plain local folder, so nothing about correctness depends
on knowing that. The only cost of dropping it is that a genuine first run
waits out the same bounded retry window (a few minutes, at most once per
user, with the GUI already usable in degraded mode throughout) instead of
bootstrapping promptly — not worth adding a dependency on confirming this
organization's OneDrive/Documents configuration for. If a real complaint
about first-run bootstrap latency ever surfaces, revisit this as a
targeted follow-up rather than building it in now.

This changes first-run bootstrap timing, not just retry-on-known-existing-
data behavior, so it needs explicit project-owner sign-off separately from
the rest of this proposal before implementation.

### Degraded mode: block functionality visibly, not startup

Project owner requirement (2026-08-28): silently running on defaults, as
today, is not acceptable even once the retry mechanism above exists —
retries can still take minutes. The user must be able to see that settings
have not loaded yet, and most functionality must be genuinely unavailable
during that window, not just quietly wrong. Telephony registration/linking
is the one exception: it does not depend on any of the five stores above
(it already succeeds independently today, per the log's `AllocNumber.xml`/
`GetEvent.xml` exchanges completing while every other loader failed) and
must keep working normally throughout.

**Chosen granularity: all-or-nothing** (project-owner decision, not
per-feature). A single readiness state covers the first-run probe above
plus all five stores (`settings.ini`, hotstrings, package settings, speed
dial, SMS default texts); functionality stays blocked until every one of
them has succeeded, even if, say, only the SMS default texts are still
retrying. This is simpler to build and to explain to the user than gating
each feature independently, at the cost of sometimes blocking a feature
whose own data actually already loaded fine.

**What "largely blocked" means concretely**, while that combined readiness
state is not yet true — finalized 2026-08-28 against a mockup (see below):
data-dependent content is **hidden outright, not dimmed/disabled**. An
earlier draft of this proposal showed disabled/grayed controls so their
presence stayed visible; the project owner rejected that in favor of
hiding, including every control that could trigger a write (save buttons
included) — nothing partially-loaded should be reachable at all, not even
in a visibly-inert state.

- **Overzicht page:** the banner plus the registration card (top of the
  page) are the only things shown. Belactie, Tekstvervanging, and Gebruik
  — the three lower cards — are hidden entirely, not shown disabled.
- **Telefonie, Hotstrings, and Instellingen pages:** each shows only the
  banner plus a short centered message; the page's entire normal content
  (speed-dial list/editor, hotstring list/editor, storage/import/SMS
  settings) is hidden, **including every save button** — there is nothing
  left on these pages that could write partially-loaded state.
- The clipboard-number → call/SMS-action flow: suspended. This is the part
  that depends on `CallAction`/`SmsCallActionTitle`/`TextReplacement` from
  `settings.ini`, so acting on a detected number without knowing the real
  setting would risk doing the wrong thing, not just nothing. Not silent,
  though (project-owner decision, 2026-08-28): show a one-off
  `ShowNotification()` toast when a number is recognized during degraded
  mode (e.g. "Nummer herkend, maar instellingen laden nog") — otherwise the
  suspension looks like DocBot failed to notice the number at all, which is
  worse than an explained no-op.
- The tray menu's "Tekstvervanging" checkbox item (`ToggleTraySetting.Bind
  ("TextReplacement")`) reads/writes `State["TextReplacement"]` directly,
  bypassing the main window entirely: disable it too during degraded mode
  (project-owner decision, 2026-08-28), otherwise a toggle made there on the
  not-yet-loaded in-memory default would itself get overwritten the moment
  the real value loads, silently discarding what the user just set. Check
  the tray menu for any other item reading/writing degraded-mode-affected
  `State` the same direct way and apply the same rule.
- Telephony registration, the link-code flow, and the long-poll event loop:
  **unaffected, run exactly as today** — this is what stays on the
  Overzicht page's registration card.
- Help/Over and other static, non-data-dependent pages: **unaffected, not
  touched by degraded mode at all** (project-owner decision, 2026-08-28) —
  no mockup needed for them since nothing changes.
- **Sidebar status indicators (bottom-left) — both "Telefonie:" and "Tekst
  vervangen:" show a neutral, pulsing "Laden…" state**, not the normal
  green/red Actief/Inactief. This corrects an earlier draft that left
  "Telefonie:" green/"Actief" on the reasoning that registration is
  unaffected — but `RefreshSidebarStatuses()` drives that particular
  indicator from `CallAction`, not from registration status: it reports
  whether DocBot currently knows what to do with a recognized phone number,
  and until `settings.ini` has loaded, it genuinely does not know that yet.
  Registration itself stays visible and correct in the Overzicht card
  above; the sidebar dot is a different signal and must reflect its own
  real uncertainty rather than borrowing telephony's "it still works" fact.

**Making it visible, not silent:** the existing transient notification GUI
(`ShowNotification()`, D-025) is built to auto-dismiss after a few seconds
and is the wrong shape for a state that can last minutes. This needs a
persistent indicator — a banner/status area in the main window that stays
present for as long as degraded mode lasts and clears automatically the
moment the combined readiness state becomes true (refreshing the
now-unblocked page at the same time, consistent with how the shared retry
timer already refreshes each loader's own state on success).

**Mockup:** [DocBot Degraded Mode](https://claude.ai/code/artifact/defdebdf-87bd-4d38-8a2d-587eb8bbd896)
shows the finalized design — the persistent warning-colored banner
(spinner, non-dismissing), the Overzicht page with only the registration
card left standing, the Telefonie/Hotstrings/Instellingen pages reduced to
banner-plus-message, and both sidebar status dots on the neutral "Laden…"
state, against a "Normaal" comparison artboard. Colors, sidebar, and card
geometry are lifted directly from `DocBot.ahk`'s `C := Map(...)` palette
and `BuildMainGui()` layout; exact pixel positions were compressed slightly
to fit the banner into the fixed 700px-tall window and should be
re-verified during implementation, not copied as final coordinates.

The GUI shell itself must still appear immediately either way — this is
about which content that shell shows, not about delaying `MainGui.Show()`
(see the synchronous-vs-background-timer point above, which still applies
in full).

### Proposal (needs project-owner sign-off before implementation)

- Do **not** reintroduce a blocking/global startup writeability gate — that
  approach was deliberately rejected (D-026) because it makes unrelated
  functionality unavailable whenever Documents/OneDrive is briefly slow.
  This applies to the retry mechanism itself, not only to the original
  gate: `InitializeUserStorage()`, `LoadAppSettings()`, and the four JSON
  loaders all currently run synchronously *before*
  `BuildMainGui()`/`MainGui.Show()`. The **first, single, fast attempt**
  can stay exactly where it is (it fails fast today, in well under a
  second, so it does not delay the GUI) — but every *retry*, on any of
  these loaders or on the first-run probe below, must be moved to run on a
  background timer *after* the GUI is already shown, the same shape
  `Telemetry_TryEnsureInstallationId()` already uses. Leaving a multi-minute
  retry loop in the current synchronous position would delay the main
  window itself, which is the same blocking gate D-026 rejected, only
  scoped to fewer call sites.
- Generalize the existing telemetry installation-ID pattern (D-027/D-028),
  but split *scheduling* from *error handling*: since all five loaders sit
  on the same Documents/OneDrive-backed folder and the log shows them
  failing and recovering together, use **one shared retry timer** (the same
  quick/slow cadence already used for the installation ID) instead of five
  independent timers duplicating the same schedule and logging the same
  moment five times over. On each tick, the shared timer re-runs every
  loader that has not yet succeeded and, per loader, refreshes only that
  loader's in-memory state and any already-built GUI list/controls on
  success — mirroring how `Telemetry_TryEnsureInstallationId()` calls
  `Telemetry_Start()` once it succeeds.
  Keep each loader's *own* success/failure and its own `Opslagfout` message
  fully independent, though: coupling the retry trigger to a shared timer
  must not couple the diagnosis. A loader that keeps failing for an
  unrelated reason (a locked file, a corrupt document, antivirus scanning)
  once its siblings have already recovered must still fail visibly and
  distinctly on the next shared tick, not be silently carried along by
  whichever loader succeeds first — do not collapse the five distinct
  `Opslagfout` messages into one.
- Close the silent gap in `LoadAppSettings()` specifically: log a baseline
  `Opslagfout` (or equivalent) when `ConfigFile` does not resolve, rather
  than returning with no diagnostic trace, so "not yet available" is
  distinguishable from "first run" in the standard log.
- Fold the `PhoneActions`/`LongHotstringActions`/`SmsActions` counter reads
  into the same retry/confirmation discipline already used for the
  installation ID, so a transient read failure can no longer cause
  `Telemetry_WriteCounter()` to overwrite a real cumulative count with a
  session that started from a false `0`.
- This is a startup-timing race that only reproduces through the real
  autostart trigger on a managed Windows workstation, not an interactively-
  launched interpreted or compiled run (`docs/DECISIONS.md` D-037) — but
  that validation is the **last** step, against the finished fix, not a
  precondition for starting work. Waiting for the race to spontaneously
  recur again on its own is not a reliable way to test it: the original log
  is sufficient evidence the bug is real, and there is no way to force an
  as-yet-unfixed build to hit the race on demand. Once there is a build to
  test, deliberately simulate the delayed-storage condition instead of
  waiting for a natural recurrence — e.g. briefly deny/delay access to the
  profile folder (or the specific JSON files) at the exact moment autostart
  fires — so the retry/probe/degraded-mode behavior can be exercised and
  confirmed on demand rather than hoped for.
- Record the generalized retry approach in `docs/DECISIONS.md` (mirroring
  D-027/D-028) and update `docs/PROJECT_CONTEXT.md` §4.7 once implemented.

### Implementation status (2026-08-31)

Implemented on `claude/docbot-autostart-telemetry-s8bhu8`
(`AppVersion 2.4-autostart-storage.1` through `.7`) and merged into
`develop` via PR #63 (2026-08-31; the PR was initially opened against
`main` by mistake and retargeted to `develop` before merging, matching the
normal branch workflow). Recorded as `docs/DECISIONS.md` D-063 (shared
retry + write-probe) and D-064 (degraded-mode UI), both now marked
functionally validated on Windows. The `.5`/`.6`/`.7` commits are fixes
from that validation pass, not new scope — see the last scope item below.

### Scope

- [x] Design and implement the shared-timer/per-loader-diagnosis retry
  approach described above for `LoadAppSettings()`, hotstrings, package
  settings/selections, speed dial, and SMS default texts.
- [x] Fix the silent no-log early return in `LoadAppSettings()`.
- [x] Get explicit project-owner sign-off on, then implement, the
  write-probe approach for `InitializeUserStorage()` described above
  (create a temporary folder under `A_MyDocuments`, re-check for a real
  profile, then either discard the probe or rename it into place), so a
  not-yet-mounted OneDrive is no longer indistinguishable from a genuine
  first run.
- [x] Reuse the existing "re-check immediately before use, let an existing
  value win" pattern from `Telemetry_TryEnsureInstallationId()` for the
  probe's rename step, to handle two DocBot instances racing to claim
  `UserDataDir`.
- [x] Reuse the existing `PruneAbandonedProblemReportDirs()`-style sweep
  (P1 "Remove temporary problem-report artifacts") to clean up an orphaned
  probe folder left behind by a crash between creation and rename/delete;
  give the probe folder a similarly recognizable name rather than adding a
  second cleanup mechanism.
- [x] Ensure every retry loop (loaders and the first-run probe alike) is
  wired to run on a background timer after `MainGui.Show()`, not left in
  the current synchronous position before it.
- [x] Address the counter-zeroing/overwrite risk in
  `Telemetry_ReadCounter()`/`Telemetry_WriteCounter()`.
- [x] Introduce a single combined readiness flag covering the first-run
  probe and all five stores, and gate hotstring expansion, the
  clipboard-number call/SMS-action flow, package manager, speed dial, and
  SMS default-text settings on it (all-or-nothing, per project-owner
  decision) — while leaving telephony registration/linking/event-polling
  and the Help/Over pages unaffected.
- [x] Implement the finalized "hide, don't dim" behavior per the mockup:
  on Overzicht, render only the banner and the registration card while the
  readiness flag is false (Belactie/Tekstvervanging/Gebruik not shown at
  all); on Telefonie/Hotstrings/Instellingen, render only the banner plus a
  short message (no list, no editor, no save button of any kind).
- [x] Drive **both** sidebar status dots from the combined readiness flag,
  not only their own setting — `RefreshSidebarStatuses()` sets
  "Telefonie:" from `CallAction` and "Tekst vervangen:" from
  `State["TextReplacement"]` the same way, so both currently risk showing
  a stale/default green-or-red state while degraded rather than "Laden…".
  Registration itself stays correctly visible in the Overzicht card
  regardless — only these two sidebar dots need the neutral state.
- [x] Show a one-off `ShowNotification()` toast when a clipboard phone
  number is recognized while degraded mode is active, rather than
  suspending the call/SMS-action flow silently.
- [x] Disable the tray menu's "Tekstvervanging" checkbox item during
  degraded mode (and audit the rest of the tray menu for any other item
  that reads/writes `State` the same direct way), so a toggle made there
  on a not-yet-loaded default can't be silently overwritten once the real
  value loads. The audit found a second item needing the same gate: the
  "Belactie" submenu (`SetTrayCallAction()`) writes `State["CallAction"]`
  and calls `SaveAppSettings()` exactly like `ToggleTraySetting()` does —
  both are now disabled while degraded.
- [x] Design and implement a persistent (not auto-dismissing) in-GUI
  banner for degraded mode, distinct from the existing transient
  `ShowNotification()` toast, that clears automatically once the combined
  readiness flag becomes true and the now-unblocked page refreshes. Match
  the mockup's banner style (warning-colored, left accent bar, spinner)
  as a starting point, re-verified on Windows. Implemented as a plain
  warning-colored bar with a left accent, without the mockup's animated
  spinner: a Segoe MDL2 icon glyph mixed into the same `AddText` string as
  regular text does not render as an icon without `AddFlatButton()`'s
  custom-draw machinery, and a dedicated animation timer for one static
  status bar wasn't judged worth the added complexity.
- [x] Update `docs/DECISIONS.md` and `docs/PROJECT_CONTEXT.md` §4.7.
  Also updated `docs/ARCHITECTURE.md` §5/§7.4/§13/§14.1 (not originally
  listed here, but the auto-execute sequence and user-data architecture
  sections were now stale) and README's Telemetrie section (the installed
  counters' read-confirm-before-write behavior changed, even though the
  payload fields themselves did not — see `docs/DECISIONS.md` D-063).
- [x] Update the README changelog; assess whether the telemetry
  documentation needs changes (the payload/fields themselves should not
  change, only when/how reliably the counters are read). Assessed: fields
  unchanged, reliability behavior changed and is now documented (see above).
- [x] **Last step, against the finished build:** validated on Windows
  (2026-08-31) by deliberately simulating delayed/denied storage on demand,
  exactly as proposed above, rather than waiting for the original autostart
  race to recur naturally:
  - `FileShare 'None'` exclusive read locks (via a short PowerShell script)
    held across two background retry ticks on all five already-existing
    `DocBot-test`/`DocBot-dev` profile files, confirming the retry cadence
    (first background attempt at ~60s, then every ~60s through the fourth,
    then hourly) and the expected non-blocking `ShowNotification()` toast
    per failed retry (`ReportStorageError()`, D-063) — not a MsgBox, and
    each retry reported independently as designed.
  - `icacls ... /deny "user:(WD,AD)"` on `Documents` itself (no profile
    folder yet), confirming `UserStorageProbe_TryBootstrap()`'s write-probe
    retries without crashing or hard-exiting, and recovers cleanly once the
    deny is lifted (`icacls ... /remove:d`).
  - Page navigation to Hotstrings while degraded, and the degraded-to-ready
    recovery transition, were both explicitly exercised this way and
    **found two real regressions**, not caught by source review alone:
    `ApplyHotReplacementEditorState()` re-showed the Hotstrings editor form
    (input field + expand button) after `ShowPage()`'s degraded-gate loop
    had already hidden it, because it recomputed visibility from
    `CurrentPage` alone with no `StorageAllReady` check — the save button
    itself stayed correctly hidden, so no partially-loaded state could
    actually be written, but the visible field contradicted the banner.
    Separately, `BuildTrayMenu()`'s "Snelkiesnummers" quick-call section
    was never gated on `StorageAllReady` at all, so the tray menu showed
    the code-default speed-dial numbers as clickable during degraded mode
    and a click placed a real call (`CallSpeedDialEntry()` →
    `IPT_callNumber()`) on unconfirmed data — more consequential than the
    first finding since it reaches a real side effect, not just a visible
    inconsistency. Both fixed and documented as validation notes on D-064
    before merging (`AppVersion 2.4-autostart-storage.6`/`.7`).
  - **Residual gap, not blocking:** the Instellingen SMS-default-text-field
    refresh path (`RefreshInstellingenValuesAfterReady()` /
    `ApplySmsDefaultTextFieldState()`) was not separately exercised in this
    round, and no `debug.log` excerpt from this validation pass was
    captured/attached for the record. Neither reopens this item — the core
    race, retry cadence, degraded-mode gating, and recovery are now
    confirmed working end-to-end with two real regressions caught and
    fixed — but pick up the SMS-field path opportunistically if it is ever
    touched again, and prefer capturing a `debug.log` excerpt the next time
    this condition is deliberately reproduced.

This changes `DocBot.ahk`/`Telemetry.ahk` behavior. Implement on a dedicated
feature/fix branch from the then-current `develop`, update the
branch-specific `AppVersion` in every commit that changes `DocBot.ahk`, and
validate on the managed Windows workplace before merging.

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

## P1 — Run `--selftest` automatically when compiling, with results visible on the console (done)

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
  regardless. **Confirmed on a fourth Windows run (2026-08-26) by the
  project owner:** declining all three questions now genuinely skips the
  `EPD_Machine` copy.
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
`claude/next-5-todo-tasks-h6kn5k` (merged via PR #57/#58).
**Fully validated on a real managed Windows workstation by the project
owner (2026-08-26):** the automatic post-compile `--selftest` run, the
readable results file output (including after the BOM fix), the
single-keypress J/n prompts (D-061), and the `DO_EPD_COPY` decline fix all
confirmed working end to end. This item is closed.

---

## P2 — Remove the optional `itemCount` package-manifest check (done)

**Status: implemented** on branch `claude/remove-itemcount-controle-94h6jc`.

Reported by the project owner (2026-08-25): the optional `itemCount` field
on a bundled package (checked in `LoadBundledPackageFile()`, `DocBot.ahk`
around line 6886) threw a loading error whenever it did not exactly match
`package["items"].Length`:

```
Pakket {id} vermeldt {itemCount} items, maar bevat er {items.Length}.
```

`items.Length` is already the authoritative count; `itemCount` was a
separately maintained manifest field that had to be kept in sync by hand
whenever a package's item list changed on the network share. It added no
value over just counting `items` and only created a way for an otherwise
valid package to fail to load.

- [x] Remove the `itemCount` consistency check from `LoadBundledPackageFile()`.
  Nothing else in `DocBot.ahk` read or wrote the field, so there was no
  further field handling to remove.
- [x] Checked for other readers/writers (package authoring tooling, other
  loaders, `docs/MIGRATIONS.md`) — only `docs/MIGRATIONS.md` documented the
  check; updated it.
- [x] `docs/ARCHITECTURE.md` never documented `itemCount`, so no change
  needed there.
- [x] Dropped the now-unused top-level `itemCount` field (and the
  never-validated per-category `itemCount`) from the `packages/*.json` data
  files, so nothing still implies it needs to be kept in sync by hand.

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

## P2 — Harden the standard-log format migration check beyond the first 256 bytes (done)

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

- [x] Decide on an approach: e.g. validate every line's format (not just the
  header) during `InitializeDiagnosticLogging()`, or make
  `PruneExpiredDebugLogFile()`'s "does this line match a known format"
  check exhaustive (current format + every known legacy format) with
  unconditional expiry for anything that matches no known format at all,
  rather than the current conservative "keep unknown content" default.
  Chose the latter — see `docs/DECISIONS.md` D-062.
- [x] Weigh the tradeoff explicitly: the current conservative default
  favors not deleting recent-but-corrupted entries; a stricter default
  favors not indefinitely retaining unredacted content. Record the decision
  in `docs/DECISIONS.md`. Recorded as D-062.
- [x] If changed, keep it consistent with the "malformed/legacy content must
  not block startup" invariant from the seven-day-retention work. The new
  `ClassifyDebugLogChunk()` helper only drops the unrecognized entry itself
  during the existing daily/startup maintenance pass; it never blocks or
  interrupts startup (D-062).

Implemented on `claude/standaardlog-format-validation-hez3ak`. Functionally
validated on Windows (`docs/DECISIONS.md` D-037, 2026-08-26): `--selftest`
is green (including `TestClassifyDebugLogChunk`, after fixing a `Trim()`
empty-tail bug the test itself caught) and a manually-appended
unrecognized-format line was confirmed pruned from a live `debug.log` on
the next maintenance pass.

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

## P2 — Add an SMS-action counter (GUI overview + telemetry)

Filed by the project owner (2026-08-26). DocBot already tracks and shows
two usage counters — "Belacties" (`TelemetryPhoneActions`) and "Lange
hotstrings" (`TelemetryLongHotstringActions`) — on the Overzicht page's
"Gebruik" card and in the telemetry heartbeat payload
(`phoneActions`/`hotstringActions`). Add a third counter for SMS actions,
in both places, following the exact same established pattern.

### Scope

- [x] Add a `TelemetrySmsActions` counter to `Telemetry.ahk`, mirroring
  `TelemetryPhoneActions`/`TelemetryLongHotstringActions`:
  `Telemetry_RecordSmsAction()`, `Telemetry_GetSmsActions()`, persisted via
  the existing `Telemetry_ReadCounter("SmsActions")`/
  `Telemetry_WriteCounter("SmsActions", ...)` helpers in the same `[Usage]`
  section of `settings.ini` the other two counters already use — no new
  storage mechanism needed. A missing key already defaults to `0` via
  `Telemetry_ReadCounter()`, so existing installs need no migration.
- [x] Call `Telemetry_RecordSmsAction()` where `RunSmsCallAction()`
  genuinely succeeds (`DocBot.ahk`, the `else` branch around line 4469-4470
  that logs "SMS-route afgerond."), not merely when the SMS option is
  offered/selected — mirroring how `Telemetry_RecordPhoneAction()` fires
  only after the dial request is actually sent (`DocBot.ahk` line 2244),
  not merely when dialing is offered. Also call `RefreshUsageStatistics()`
  there, matching the phone-action call site.
- [x] Add a third stat block (icon + label "SMS-acties" + count) to the
  existing "Gebruik" card on the Overzicht page, alongside "Belacties" and
  "Lange hotstrings" (`DocBot.ahk`, `AddCard("overzicht", 236, 516, 736,
  128)` and the `AddCardLabel`/icon blocks right after it). Implemented as
  three columns on one row (project owner's choice over a second row); the
  per-item "Lange en meerregelige vervangingen" caption that only existed
  under the hotstring stat was dropped so all three columns get equal
  treatment. Still needs Windows visual validation (spacing/legibility,
  no clipping) — not yet confirmed on a compiled build.
- [x] Update `RefreshUsageStatistics()` (`DocBot.ahk` around line 1981) to
  also refresh the new label live, matching the existing two counters
  (`OverviewPhoneActionsText`/`OverviewLongHotstringActionsText` pattern).
- [x] Add an `smsActions` field to the telemetry heartbeat payload
  (`Telemetry_SendHeartbeat()` in `Telemetry.ahk`), alongside the existing
  `phoneActions`/`hotstringActions` raw JSON properties. Explicit
  project-owner sign-off obtained 2026-08-26 for this payload addition
  (both the counter/GUI part and this payload part approved together).
- [x] Per `CLAUDE.md`/`AGENTS.md` ("Transparantie over telemetrie"): the
  README `Telemetrie` section and `docs/DATA_PROTECTION.md` payload listing
  were updated in the same change that adds the field, matching the
  actually-sent payload.
- [x] **Decided (2026-08-26):** the counter counts only genuinely
  successful SMS actions, not every attempt — confirmed by the project
  owner. "Successful" is determined the same way the caller already
  decides success/failure for logging/notifications: the existing boolean
  return value of `RunSmsCallAction()` (`DocBot.ahk` around line 4458),
  which is `true` only once DocBot has actually found/opened the right
  Edge page or tab and filled the phone number field — no new detection
  logic needed, just hook the counter to that same `else` branch that
  already logs "SMS-route afgerond." This mirrors the existing
  `Telemetry_RecordPhoneAction()` semantics: "success" means DocBot
  completed its own side of the action (the dial request was sent /
  the SMS field was filled), never the human end-of-flow outcome (the
  call was answered / the SMS was actually sent) — DocBot cannot observe
  that and, by design, never sends the SMS itself.
- [x] Update `README.md` (feature description and `Telemetrie` section) and
  `docs/DATA_PROTECTION.md` if the new field changes what's described
  there beyond the existing phone/hotstring counters' precedent.

This changes `DocBot.ahk`/`Telemetry.ahk` behavior and the telemetry
payload. Implemented on branch `claude/sms-actieteller-gui-telemetry-gv38n7`
from `develop` (`2.4-dev.2`); `AppVersion` bumped to
`2.4-sms-actieteller.1` in the same commit. Still needs Windows
visual/functional validation (D-037) before merge — nothing here has been
run on a compiled build yet.

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

### Recommended first step (proposal, 2026-08-26)

Start with **storage/migrations**, not telephony/SMS-UIA/GUI rendering. Reasons:

- It is already the most decoupled seam in the file by a proven margin:
  `tests/SelfTests.ahk` already calls `ReadSchemaVersion()`,
  `RejectNewerSchemaVersion()`, `CreateHotstringItem()`,
  `NormalizeHotstringItem()`, `AddMissingDefaultHotstrings()`,
  `CreateSpeedDialEntry()`, `AddMissingDefaultSpeedDials()`, and
  `GetUserDataProfile()` in isolation, with only a temporary
  `global LocalConfig` substitution and no GUI/network/file-I/O
  dependency. That is direct, already-passing evidence these functions
  don't entangle with global GUI state the way telephony/SMS-UIA/GUI
  rendering do.
- D-053 already flagged this exact move — extracting these functions "into
  their own included file (mirroring the existing `Telemetry.ahk` module
  boundary)" — as the natural next step, and explicitly deferred it only
  because it "cannot be validated by this agent (no Windows runtime
  available, D-037)", not because of any doubt about the seam itself.
- `Telemetry.ahk` is a live, working precedent for the target shape: a
  `#Include`d file holding related globals + functions, no GUI, included
  from `DocBot.ahk` without disturbing top-level init order.

Concrete shape: a new `Storage.ahk` (or similar name) holding exactly the
functions `tests/SelfTests.ahk` already covers, `#Include`d from
`DocBot.ahk` at the same structural point `Telemetry.ahk` is included
today. Validate with `--selftest` before and after the move (identical
pass count and lines is the cheapest possible regression check for
exactly this seam) plus a full manual Windows regression pass, on its own
dedicated branch, not bundled with unrelated feature work. Explicitly do
**not** start with telephony, SMS/UIA, or GUI rendering — those are the
seams with heavy global-GUI-control-reference and callback-binding
coupling this same section already warns about, and should only be
attempted once the storage-helpers move has proven the `#Include`/
`FileInstall`/top-level-init-order pattern works end to end without
regressions.

---

## P2 — Consider folding the telemetry retry timer into `StorageRetryLoaders`

Filed 2026-08-31, while fixing the `Telemetry_ReadCounter()`/
`Telemetry_TryEnsureInstallationId()` read-race bugs (`docs/DECISIONS.md`
D-063 validation notes).

`StorageRetryLoaders` (D-063) already unified five originally-independent
loaders onto one shared background timer because they "sit on the same
Documents/OneDrive-backed folder... fail and recover together." Telemetry's
installation ID and usage counters (`Telemetry_TryEnsureInstallationId()`/
`Telemetry_TryLoadCounters()`, `Telemetry.ahk`) were deliberately left on
their own separate timer at the time, reusing the *shape* of the existing
D-027/D-028 retry pattern rather than joining the new shared array.

That argument for staying separate looks weaker now than it did then:
telemetry reads/writes the exact same file as `LoadAppSettings()`
(`TelemetryConfigFile`/`ConfigFile` are both `settings.ini`) — a stronger
case for sharing one timer than "same backing folder" ever was. The split
already produced one real coordination bug that needed a direct patch:
counter confirmation could land after `StorageRetry_OnAllReady()`'s
one-time Overzicht refresh already ran, leaving the Gebruik card stuck on
0 until a manually-added `RefreshUsageStatistics()` call in
`Telemetry_TryLoadCounters()`'s success path fixed it (D-063 validation
note, 2026-08-31) — a symptom of two independently-completing systems
that a shared timer would remove structurally instead of papering over.

What would need solving before folding this in, not blockers so much as
shape mismatches with the existing `StorageRetryLoaders` `Fn`-returns-bool
interface:

- Telemetry is optional (`TelemetryConfig["Enabled"]`), but the usage
  counters are loaded regardless of that setting (they feed the local
  Overzicht "Gebruik" card independent of telemetry consent) — a folded-in
  loader would need to report ready immediately when telemetry itself is
  disabled, without also disabling the counter read.
- The counter loader merges pending in-session actions
  (`TelemetryPhoneActions` etc., accumulated in memory before
  confirmation) with the freshly-confirmed disk baseline on success — the
  five existing loaders don't have an analogous "reconcile with
  in-flight state" step.
- The installation-ID loader has its own extra write-then-reread
  confirmation step for the multi-instance race (`Telemetry_
  TryEnsureInstallationId()`), not present in any current loader.

None of these look hard to adapt, just different enough from the existing
five loaders that this is a real (if modest) refactor, not a drive-by
change — deliberately not bundled into the read-race bugfix that surfaced
it. Revisit as a P2 cleanup in a future development cycle, not as part of
finishing 2.4.

---

## P3 — Also offer the EPD_Machine copy question for a stable release, not only `-dev`/`-rc`

_Downgraded from P1 to P3 (2026-08-26, project-owner decision)._

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

## P3 — Change the sidebar slogan

Filed by the project owner (2026-08-26). Change the app subtitle shown
under "DocBot" in the main window's sidebar from "Telefonie voor de
werkplek" to "Een handje extra voor je werk". Classified P3 (cosmetic,
narrow-impact single-line UI text) unless the project owner wants it
prioritized higher.

### Scope

- [ ] Update the literal string in `DocBot.ahk` (`appSub := MainGui.AddText(...)`
  around line 338) from `"Telefonie voor de werkplek"` to `"Een handje
  extra voor je werk"`.
- [ ] Check the fixed-width text control it sits in (`w170`, `s9` font,
  directly under the `appTitle`/`appSub` pair at `x28 y52`) on a real
  Windows build: the new string is a few characters longer than the old
  one, so confirm it neither clips nor wraps awkwardly against the nav
  buttons starting at `y=110` — widen the control or adjust its position
  only if it actually does.
- [ ] This is the only in-repo occurrence of "Telefonie voor de werkplek"
  (confirmed via a full-repo search) — no README, About-screen, or other
  duplicate copy needs updating. Note this is a different string from the
  GitHub repository's own "description" metadata field ("DocBot is een
  AutoHotkey v2-hulpmiddel voor medewerkers met twee hoofdfuncties..."),
  which lives in GitHub's repo settings, not in a tracked file — out of
  scope here unless the project owner separately wants that changed too.
- [ ] Consider whether the new slogan should also be reflected in the
  README's own product description at the top, for consistency between
  the app and its documentation — project-owner call, not assumed here.

This changes `DocBot.ahk` behavior (visible UI text). Implement it on a
dedicated feature/fix branch from the then-current `develop` and update
the branch-specific `AppVersion` in the same commit.

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
- **Startup onboarding tips based on zero-usage counters:** implemented on `claude/onboarding-tips`. A yellow dismissible hint banner on Overzicht (`TipBannerSurface`/`-Accent`/`-Link`/`-CloseButton`, `EvaluateStartupTip()`) randomly picks one eligible tip per session — phone/hotstrings/sms zero-usage tips plus a "closing hides DocBot in the tray" tip that replaced the old fixed Overzicht footer text. Eligibility needs both a true condition and enough time since last shown (`[Tips]` section in `settings.ini`, separate from telemetry's `[Usage]`): at least 10 days for a tip's first `TipRepeatCapCount` (5) shows, then at least `TipLongTermIntervalMonths` (6) months — a tip never stops permanently, it just drops to a much lower frequency after the cap. Pending compiled-Windows validation (D-037).

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
