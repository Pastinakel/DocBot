# DocBot — Architecture

_Last updated: 2026-08-16. Repository facts refer to stable DocBot 2.2 (`main`, tag `v2.2`) and the start of the 2.3 development line unless noted otherwise._

## 1. Architectural style

DocBot is a Windows desktop application written in AutoHotkey v2. The architecture is pragmatic rather than layered in the classic sense:

- `DocBot.ahk` contains most application behavior and UI;
- `Telemetry.ahk` is a separate optional module;
- third-party libraries are included directly from `ThirdParty/`;
- local environment/secrets are injected through ignored `DocBot.local.ahk`;
- bundled content is stored as JSON under `packages/`;
- persistent user state is stored as INI/JSON files outside the repository.

The main script is large, but it is organized by subsystem and uses explicit global maps/controls as the primary shared-state mechanism. Refactoring it into many modules may be desirable eventually, but should not be attempted casually because startup order, global initialization, GUI control references, hotstring callbacks, AutoHotkey event binding, and compiled `FileInstall` behavior are tightly coupled.

## 2. Compile-time and startup dependencies

`DocBot.ahk` currently includes, in order:

```text
ThirdParty/JXON/JXON.ahk
ThirdParty/ColorButton/ColorButton.ahk
Telemetry.ahk
ThirdParty/UIA-v2/UIA.ahk
ThirdParty/UIA-v2/UIA_Browser.ahk
DocBot.local.ahk   (optional include at source level; required to pass validation)
```

`DocBot.local.ahk` is deliberately ignored by Git. It provides the real values for:

- internal telephony base URL and endpoints;
- local default speed-dial entries;
- local default hotstrings;
- SMS action configuration;
- optional telemetry configuration and webhook URL.

`DocBot.local.example.ahk` is the only safe versioned template.

The application validates local configuration immediately. Missing/invalid required local values produce a blocking configuration error and exit. This includes an HTTPS-only check: `ValidateLocalConfiguration()` rejects a non-`https://` `Telephony.BaseUrl`, and `ValidateSmsCallActionItem()` rejects a non-`https://` `SmsCallAction.Url`, using the same `i)^https://` pattern already used for `Telemetry.WebhookUrl` (see `docs/DECISIONS.md` D-043).

## 3. AutoHotkey v2 startup-order constraint

This is a critical implementation detail.

AutoHotkey v2 executes top-level statements in file order. Function definitions are parsed/skipped during auto-execute, but a global variable initializer that appears later in the source has not executed yet when earlier top-level code or GUI construction needs it.

Therefore, all globals used directly or indirectly during initial GUI construction must be initialized in the top globals block before the auto-execute section. Known examples include GUI state plus rendering state such as `RoundQueue`, rounded-control metadata, control-position maps, bitmap/GDI state, and shared dialog state.

Do not move required global initializations into a later subsystem section just because that section is conceptually related.

## 4. High-level component map

```text
                   +-------------------------+
                   |   DocBot.local.ahk      |
                   | local config / secrets  |
                   +------------+------------+
                                |
                                v
+----------------+     +--------+---------+      +------------------+
| ThirdParty     |---->|    DocBot.ahk    |<---->|  Telemetry.ahk   |
| JXON           |     | main app + GUI   |      | optional status  |
| ColorButton    |     +---+---+---+---+--+      +---------+--------+
| UIA-v2         |         |   |   |   |                   |
+----------------+         |   |   |   |                   |
                           |   |   |   |                   v
                           |   |   |   |          Power Automate/
                           |   |   |   |          Teams webhook
                           |   |   |   |
                           |   |   |   +------> Edge/UI Automation
                           |   |   |            SMS helper
                           |   |   |
                           |   |   +----------> internal telephony
                           |   |                POST endpoints
                           |   |
                           |   +--------------> user data
                           |                    Documents + LocalAppData
                           |
                           +------------------> bundled packages
                                                packages/*.json
```

## 5. Auto-execute sequence

The current startup flow in `DocBot.ahk` is approximately:

1. validate local configuration;
2. calculate `AppVersion` and choose user-data profile;
3. initialize global UI/config/state objects;
4. `InitializeUserStorage()`;
5. best-effort pin the user-data folder locally (`MarkUserStorageAlwaysAvailable()`);
6. initialize bundled package cache/data;
7. load application settings;
8. initialize personal hotstring storage/migrations;
9. initialize package settings/migrations;
10. initialize speed-dial storage/migrations;
11. register/reload runtime hotstrings;
12. initialize telemetry;
13. process update-restart command-line state if present;
14. build the main GUI and tray menu;
15. register Windows messages and exit handler;
16. show GUI and apply custom visual rendering;
17. start clipboard polling;
18. start registration-button countdown timer;
19. request telephony registration and start chained event polling;
20. start/check `signal.txt` update/shutdown coordination.

Changing this order can have user-data, UI, or network side effects. Treat initialization order as behavior, not formatting.

## 6. Shared state model

### 6.1 `State`

`State` is the main runtime state map. Important fields include:

- selected call action;
- selected SMS action title;
- text replacement enabled/disabled;
- AutoSave state;
- active personal-hotstring file;
- nested `State["IPT"]` telephony state.

`State["IPT"]` tracks values such as:

- linked user telephone number;
- current registration/link code;
- update/poll flags;
- most recently detected clipboard number;
- last registration request tick.

### 6.2 GUI globals

The application keeps many control references globally because event callbacks and page refresh functions need them. Examples include:

- main GUI/page/nav structures;
- registration texts and refresh button;
- call-action selector;
- hotstring ListView/editor controls;
- speed-dial ListView/editor controls;
- package-manager window and ListViews;
- sidebar status indicators;
- custom-notification GUI;
- debug window controls;
- call/SMS dialog keyboard state.

This is one reason an aggressive module split would require care.

### 6.3 Network request globals

Telephony intentionally uses separate module-level request references:

- registration request;
- polling request;
- dial request.

They are separate so a new request cannot overwrite the object reference needed by another unfinished callback.

Telemetry separately holds its own asynchronous request object.

## 7. User-data architecture

### 7.1 Release-channel profiles

`AppVersion` selects one of three Documents profiles:

```text
stable numeric version       -> %MyDocuments%\DocBot
-dev or -rc prerelease       -> %MyDocuments%\DocBot-test
other named prerelease       -> %MyDocuments%\DocBot-dev
```

Purpose: a feature/fix or RC build must never mutate/migrate production user data simply because it is launched by a developer/tester.

Bootstrap behavior:

- create missing target profile;
- for test, copy once from stable when appropriate;
- for dev, prefer copying once from test, otherwise stable;
- rewrite internal profile paths where needed;
- then run normal schema migrations;
- never overwrite an already-existing target profile during bootstrap.

### 7.2 Persistent files

Primary persisted state:

```text
settings.ini             application settings + telemetry ID/counters
hotstrings.json          personal hotstrings
package-settings.json    package enabled/disabled/conflict choices
speeddial.json           speed-dial entries
```

Storage routines use defensive patterns such as `.bak`, temporary files, validation, and replacement where implemented.

### 7.3 LocalAppData

LocalAppData is used for machine-local/runtime artifacts, notably:

- `debug.log`;
- extracted/cached bundled packages.

Development package extraction is separated from production package cache to avoid test builds overwriting production cache.

## 8. Migrations

There is no standalone migrations directory. Schema migrations live in application logic and are keyed by explicit schema versions.

Current global schema concepts include:

- personal hotstring schema;
- bundled-package schema;
- package-settings schema;
- speed-dial schema.

Rules for migrations/default additions:

- migration must be one-time/idempotent;
- identify logical records by their functional/stable key;
- never overwrite a user-edited personal value;
- if a default was intentionally removed by a user, do not re-create it every startup;
- preserve backwards compatibility with older storage filenames/formats where explicitly supported.

When adding a new default through local configuration, advance the relevant schema and make the addition conditional on the functional key not already existing.

`docs/MIGRATIONS.md` is the detailed registry: which schema version added
which field/default per storage format, which legacy filenames are still
read, and how to add a new migration. `ReadSchemaVersion()` and
`RejectNewerSchemaVersion()`, defined once in `DocBot.ahk` immediately
before `InitializeBundledPackages()`, are the shared version-parsing/
version-ceiling helpers all four loaders use; add a new schema by following
the same pair of calls rather than reimplementing the check inline.

## 9. Hotstring runtime architecture

### 9.1 Sources

Runtime hotstrings are resolved from two conceptual sources:

- personal hotstrings (`hotstrings.json`);
- bundled package items (`packages/*.json` + package settings).

The system computes effective winners/conflicts before registering dynamic AutoHotkey hotstrings.

### 9.2 Personal model

A personal item keeps one replacement value. Rendering/execution mode is derived, not stored as a separate domain type.

Execution paths:

```text
short + simple text  -> normal dynamic hotstring replacement
long/multiline       -> callback -> SendText + explicit Enter handling
contains key tokens  -> key-command-compatible path
```

Dynamic tokens such as date/time are expanded at execution time, not when saved.

### 9.3 Clipboard boundary

Hotstring execution must never copy replacement text through the Windows clipboard. Clipboard ownership is an architectural boundary because the telephony feature continuously watches it for numbers. Reusing it for text expansion introduces races and user-data corruption risks.

## 10. Bundled package architecture

`packages/manifest.json` declares the package catalogue. Package files contain stable IDs and items.

At runtime/build:

- package files are bundled/extracted;
- manifest and package structure are validated;
- duplicate triggers/item counts/schema consistency are checked;
- effective conflicts are indexed;
- the package manager presents package/item states without using display names as storage IDs.

User settings store only choices, not package text. This allows package content to evolve with the application while user overrides remain explicit.

When a user edits or saves a package item as personal, the application writes a complete personal copy. That copy remains valid even if the bundled source later changes or disappears.

## 11. Telephony architecture

### 11.1 Configuration and state

- technical configuration: `IPTConfig`;
- live state: `State["IPT"]`;
- real URLs/endpoint names: local config only;
- `IPTConfig["URL"]` is built directly from the validated (HTTPS-only)
  `Telephony.BaseUrl`, so every request built from `IPTConfig["URL"]`
  inherits that guarantee without a separate per-call check
  (`docs/DECISIONS.md` D-043).

### 11.2 Request lifecycle

All telephony calls are POST.

Core flows:

```text
IPT_register()
  -> request registration/link information
  -> update registration UI/state

IPT_poller()
  -> issue one long/event poll
  -> IPT_PollResponse()
  -> process event/state
  -> schedule/start next poll after completion

IPT_callNumber()
  -> normalize/validate number
  -> ensure linked phone unless this is the linking call
  -> issue dial request
  -> update diagnostics/telemetry where appropriate
```

The event loop is chained rather than a fixed periodic timer to avoid overlapping long polls.

Clipboard-triggered dialing is a separate entry path into the same call gate:

```text
ClipBoardPoller()
  -> detect a clipboard sequence-number change
  -> normalize (external Dutch number / internal four-digit number)
  -> no match: ignore
  -> match: SetClipBoardNumber() then
       HandleClipboardNumberDetected() / HandleInternalClipboardNumberDetected()

Handle...ClipboardNumberDetected()
  -> CloseExistingPhoneActionDialog() first, unconditionally
       (closes a still-open dialog from a previous, unhandled detection;
       shows a short notification when it actually closes one)
  -> per CallAction: do nothing / show confirmation dialog /
       call directly via IPT_callNumber() / show call-or-SMS choice dialog
  -> ClearClipBoardNumber() once the action is handed off, completed, or
       cancelled (call placed, SMS started, dialog cancelled/closed, or no
       action configured)
```

At most one call-action dialog (confirmation, or the cancel/SMS/call choice)
may be open at a time; a newer clipboard detection always resolves — by
closing — whatever an older detection left open, regardless of which action
the new detection then takes. Manual dial paths (speed dial, right-click,
linking call) call `IPT_callNumber()` directly and do not go through this
close step, so they intentionally leave an open dialog untouched.

### 11.3 Number normalization

Number normalization is centralized. Internal four-digit numbers intentionally use a distinct policy path because four arbitrary digits have a higher false-positive probability than a full telephone number.

## 12. SMS / Edge automation architecture

SMS support is an assisted workflow, not a messaging service.

Configuration per SMS action includes user-facing and technical fields such as:

- `Title`;
- `WindowTitle`;
- target URL;
- target field `AutomationId` / field identifier.

Flow:

1. user chooses SMS from the call-action dialog;
2. validate that the number is an eligible mobile number;
3. locate/activate the configured Edge context;
4. if the relevant page is a background tab, use UI Automation to select it;
5. if it does not exist, open the configured URL;
6. locate the telephone input through UIA and fill it;
7. JavaScript fallback may be used if UIA cannot complete the field operation;
8. stop: the user reviews and sends manually.

This preserves a deliberate human-in-the-loop safety boundary.

## 13. GUI and rendering

The UI consists of a fixed main window with sidebar pages, cards, custom buttons/toggles, ListViews, inline editors, and separate modal/auxiliary windows.

Notable rendering behaviors:

- custom colors are held in a shared color map;
- rounded controls and flat/custom button rendering are applied after GUI creation/show;
- some controls require an explicit redraw/repaint after show to avoid initial native Windows borders/styles;
- the call/SMS choice dialog keeps explicit keyboard-selection state and receives `WM_KEYDOWN` centrally.

Managed Windows constraints matter: native shell notifications are not trusted for critical feedback because group policy can suppress them without an AutoHotkey error.

## 14. Telemetry architecture

`Telemetry.ahk` owns configuration, identity, counters, scheduling, payload construction, and its own HTTP request.

### 14.1 Identity

The installation ID is a generated GUID persisted in `settings.ini`.

Algorithm:

```text
read existing InstallationId
  -> if present: use immediately, no write
  -> if absent: generate pending GUID
      -> IniWrite
      -> read back
      -> only promote to active ID if exact value matches
      -> otherwise retry later
```

Retry behavior is intentionally asynchronous so temporary OneDrive failure does not block the entire application.

### 14.2 Heartbeat scheduling

Default interval is 15 minutes. Startup heartbeat is delayed briefly so telephony state has time to initialize.

### 14.3 Payload boundary

Telemetry receives only status/counters. It must remain separate from content-bearing data such as clipboard text, telephone numbers, hotstring text, package text, or local secrets.

README disclosure is part of the architecture contract: payload changes and documentation changes belong in the same change series.

## 15. Diagnostics architecture

### 15.1 Baseline logging

The normal application maintains a bounded/buffered background debug log and flush scheduling. It is intended to provide useful troubleshooting context without enabling highly detailed/sensitive tracing all the time.

The developer-only debug UI is gated by Windows account in current code.

Retention is enforced per log entry, not per file: `RunDiagnosticsMaintenance()` runs once at startup and then on a repeating 24-hour timer, and `PruneExpiredDebugLogEntries()` removes individual entries older than seven days from both the active `debug.log` and the rotated `debug.log.oud`, based on each entry's own leading timestamp rather than file modification time (see `docs/DECISIONS.md` D-044). This exists independently of, and does not change, the ~2 MB size-based rotation in `FlushDebugLog()`.

### 15.2 Integrated problem reporting and extended logging

The current DocBot 2.2 code contains the `Probleem melden...`
flow. Help and the tray menu open the same reporting GUI and session state.
`ProblemReportSession` is held in memory and tracks the phase, consented logging
state, start time, user description, temporary log path, and finalization lock.

The data flow is:

```text
direct report
  -> optional user description + redacted standard log
  -> temporary report directory with loose files (no ZIP)
  -> Outlook draft (files attached individually) or explicit manual fallback

explicit consent
  -> temporary extended log under %LocalAppData%\DocBot
  -> raw copies of diagnostic events (telemetry webhook remains redacted)
  -> executed hotstring trigger/replacement + detailed SMS/UIA events
  -> stop logging and flush buffers before packaging
  -> description + standard log + extended log as loose files in %TEMP%
  -> Outlook draft (files attached individually) or explicit manual fallback
```

Architectural boundaries:

- the standard log remains centrally sanitized at all times;
- unredacted detailed logging cannot start without the explicit checkbox;
- runtime hotstrings are re-registered on session start/stop so modes that
  normally use native replacement can be observed only during consent;
- closing the GUI preserves the in-memory reporting session, while process
  exit/restart stops it and deletes the temporary extended log;
- local configuration is never added to the report package;
- report files are attached to Outlook individually rather than zipped —
  building the ZIP through the Explorer shell namespace proved unreliable
  (or entirely unavailable) on some group-policy/EDR-hardened workplaces,
  causing report finalization itself to fail (see `DECISIONS.md` D-041);
- finalization stops extended logging before Outlook or fallback work, so an
  external mail failure cannot leave the UI claiming that logging is active;
- successful completion resets the in-memory session and removes its
  detailed log; the temporary report *directory*'s lifecycle is now
  independent of that session reset (see below) rather than tied to it;
- Outlook automation failure degrades to `mailto:` where possible, Explorer
  opening the report directory, and visible manual attachment instructions.

**Report-directory lifecycle (see `docs/DECISIONS.md` D-044):** the
temporary `%TEMP%\DocBot_diagnose_<stamp>` directory is not kept
indefinitely. On the Outlook success path, `OpenProblemReportEmail()`
deletes it only after verifying Outlook's attachment count matches and
`mail.Display()` has succeeded — at that point the file bytes already live
inside the mail item, independent of the temp files, and any earlier
failure in that same code path still reaches the fallback with an intact
directory. On the manual-fallback path, `OpenProblemReportFallback()`
deliberately leaves the directory in place (the user may still need to
attach the files by hand) and instead asks explicitly whether it can be
cleaned up now, defaulting to "no". Whatever is left behind by either
path — an abandoned fallback directory, or one orphaned by a crash between
directory creation and finalization — is bounded by the same daily
`RunDiagnosticsMaintenance()` timer as the standard-log retention above:
`PruneAbandonedProblemReportDirs()` deletes any `DocBot_diagnose_*`
directory older than seven days, based on the timestamp DocBot encodes in
the directory name itself. The loose extended-log file written by
`StartExtendedProblemLogging()` (`%LocalAppData%\DocBot\problem-report-<stamp>.log`)
has the same seven-day backstop via `PruneAbandonedExtendedLogFiles()` — it
exists because `DeleteProblemReportExtendedLog()` only knows the path of
the *current* session's file, so a file orphaned by a crash, a forced
process kill, or a Windows restart mid-session had no other cleanup path.
All three sweeps log a one-line summary via `DebugLog()`, so their behavior
is observable in the standard log rather than silent.
`PruneExpiredDebugLogFile()` logs only when it actually removes entries,
to avoid daily noise on an already-clean log. `PruneAbandonedProblemReportDirs()`
and `PruneAbandonedExtendedLogFiles()` log unconditionally on every run —
deliberately, on project-owner request, so the log itself is ongoing proof
that the seven-day cleanup ran and found nothing, not just an absence of
loud failure (see `docs/DECISIONS.md` D-044 addendum 3).

The project owner completed the dedicated compiled-Windows validation of the
RC2 flow on 2026-08-09, including ZIP behavior, Outlook/fallback cases,
session state, and sensitive-data boundaries — predating the switch to loose
attachments in D-041. The broader full-RC3 acceptance test, covering the
loose-attachment behavior together with the rest of the application, was
subsequently completed and accepted before the 2.2 release (see
`docs/TODO.md`). A compiled test build of the D-044 retention/cleanup
behavior (2026-08-17) confirmed both the standard-log retention and the two
directory/file sweeps work correctly on a managed Windows workplace.

## 16. Update/restart architecture

The deployed app may be running from a central/shared environment. Update coordination uses a `signal.txt` file polled by clients.

The build/deployment batch can:

- request client shutdown through the signal;
- attempt replacement repeatedly for a bounded period;
- verify copied executable bytes;
- always remove the temporary update signal;
- register/use a one-shot scheduled Windows task to restart the application;
- preserve whether the application had been active, backgrounded, or minimized.

This mechanism is operationally important; do not replace it with a simple overwrite while the executable may still be running.

## 17. Third-party dependency policy

Bundled external libraries live under one directory per library:

```text
ThirdParty/<library>/source
ThirdParty/<library>/LICENSE
```

Direct include paths point to those locations. Earlier temporary root-level include shims were removed.

When moving or replacing a third-party library, update together:

- source/include paths;
- the original license file;
- README file listing;
- `AGENTS.md`;
- `CLAUDE.md`.

## 18. Licensing architecture boundary

DocBot's own license and third-party licenses are different concerns.

- DocBot 2.2+ uses the repository's noncommercial project license.
- Third-party JXON, ColorButton, and UIA-v2 retain their original licenses.

Do not assume the project license can replace third-party notices.

## 19. Testing and validation reality

There is no comprehensive automated test suite today. Validation has historically consisted of some combination of:

- source/diff inspection;
- GitHub workflow checks;
- `git diff --check`;
- manual functional testing by the project owner on Windows;
- real internal-network testing for telephony;
- compiled-executable testing for release candidates.

Since PR #19, one automated gate exists: `.github/workflows/ahk-syntax-check.yml`
runs `AutoHotkey64.exe /Validate` on a `windows-latest` GitHub Actions
runner against `DocBot.ahk` on pull requests that touch `.ahk` files, using
`DocBot.local.example.ahk` as safe CI configuration. It catches genuine AHK
v2 parse/syntax errors — including the multiline-concatenation class of
regression described in D-033 — before manual Windows testing. It does not
check runtime logic, telephony/SMS/UIA behavior, or GUI rendering; those
still require the manual and internal-network validation above. The check
reached `main` as part of the 2.2 release (via `release/2.2-rc`) and is
being brought back to `develop` in the same step (see `docs/TODO.md`).

A GUI-subsystem executable such as AutoHotkey can show a blocking error
dialog on some parse failures even when told to write errors to stdout, so
the workflow does not simply `Wait` on the process; it enforces its own
`WaitForExit` timeout and force-kills a stuck process rather than trusting
AutoHotkey to exit on its own. This is a reusable pattern for any future
CI step that shells out to a Windows GUI executable.

For changes touching internal telephony, SMS/UIA, managed-Windows rendering, build/deployment, or OneDrive behavior, static inspection is not enough.

A second gate, added alongside the schema-migration registry
(`docs/MIGRATIONS.md`), runs in the same job right after the syntax check:
`AutoHotkey64.exe DocBot.ahk --selftest`. `tests/SelfTests.ahk` (`#Include`d
from `DocBot.ahk`, inert unless started with that exact argument) exercises
pure migration-support logic — `ReadSchemaVersion()`/
`RejectNewerSchemaVersion()` and the idempotency of
`AddMissingDefaultHotstrings()`/`AddMissingDefaultSpeedDials()`/
`NormalizeHotstringItem()` — without touching file I/O, the GUI, or the
network. This is deliberately narrow: AutoHotkey v2's top-level
execution-order constraint (§3) means a script that `#Include`s `DocBot.ahk`
runs its full auto-execute section, so genuine unit-test isolation for
GUI-/storage-coupled code is not practical without the kind of
modularization `docs/TODO.md` P2 "Consider gradual modularization after
2.2" explicitly treats as future, non-casual work. See `tests/README.md` for
what is and is not covered, and D-037 for why this still does not replace
manual/Windows functional validation.

## 20. Safe extension guidelines

When adding functionality:

1. identify which persistent schema/profile is affected;
2. preserve stable IDs and user overrides;
3. avoid adding new global startup dependencies below auto-execute;
4. do not repurpose the clipboard;
5. keep optional/network integrations nonfatal unless the core feature truly cannot operate;
6. keep secrets/local endpoints out of Git;
7. update telemetry disclosure if and only if payload/configuration behavior changes;
8. update README changelog for user-visible release changes;
9. increment branch AppVersion in every commit that changes `DocBot.ahk`;
10. run an actual AutoHotkey v2/Windows validation before declaring the change complete.
