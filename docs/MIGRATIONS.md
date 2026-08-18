# DocBot — Schema Migrations

_Last updated: 2026-08-18._

There is no `migrations/` directory. Migrations live in `DocBot.ahk` and are
keyed by an explicit `schemaVersion` integer per storage format. This
document is the human-readable registry that `docs/TODO.md` (P2 "Make
migration behavior easier to inspect") asked for: which schema version added
which field/default, which legacy filenames/formats are still read, and what
"idempotent" actually means for each one. The code remains authoritative —
if this document and `DocBot.ahk` disagree, verify against the code and fix
this document.

See `docs/DECISIONS.md` D-010 for why defaults are added once (not on every
startup) and `docs/ARCHITECTURE.md` §7–8 for the surrounding storage/profile
architecture.

## Shared rules

All four schemas below follow the same contract:

- a record is identified by a **functional key** (hotstring trigger,
  speed-dial name/number, package/item id) — never by array position;
- a migration **never overwrites an existing user value** for that key;
- adding a default is **one-time**, gated by `schemaVersion < N`, not
  re-applied on every later startup — if a user deletes a default, it does
  not come back;
- a file whose `schemaVersion` is higher than this DocBot build supports is
  rejected at load time with a clear error, never silently truncated or
  guessed at.

## Shared building blocks

Defined once in `DocBot.ahk`, immediately before `InitializeBundledPackages()`,
and used by all four loaders below:

- `ReadSchemaVersion(document)` — returns `document["schemaVersion"]`
  coerced to a number, or `1` when the field is absent (the historical
  default for files that predate the field existing at all).
- `RejectNewerSchemaVersion(schemaVersion, currentVersion, subject)` —
  throws a standard, formatted error when `schemaVersion > currentVersion`.
  `subject` is the Dutch noun phrase used in the message (e.g. `"Dit
  bestand"`, `"Het pakketmanifest"`, `"package-settings.json"`).

`tests/SelfTests.ahk` covers both functions directly (`--selftest`, see
`tests/README.md`).

---

## Personal hotstrings — `hotstrings.json`

`HotstringSchemaVersion` (currently **5**). Functional key: `Trigger`
(trimmed, case-insensitive for duplicate/default detection).

| Version | What it adds | Gate |
|---|---|---|
| (absent) | Treated as version 1 by `ReadSchemaVersion()`. | — |
| 1 | Every item gets a stable `Id` and an `Origin` (`custom` unless it came from a package). Items missing either field trigger a migration write. | `!rawItem.Has("Id") || !rawItem.Has("Origin")` per item |
| 5 | Locally configured default hotstrings (`LocalConfig["DefaultHotstrings"]`, real values only in `DocBot.local.ahk`) are added once via `AddMissingDefaultHotstrings()`. An existing trigger — default or user-created — is never touched. | `schemaVersion < 5` |

Versions 2–4 have no dedicated migration block in the current code. Do not
assume they historically added a specific field; nothing in the source or
`README.md` Changelog currently documents what they were for. Treat that gap
as unknown rather than guessing, and correct this row if evidence turns up.

**Always-on normalization** (runs on every load regardless of
`schemaVersion`, via `NormalizeHotstringItem()` — not a versioned
migration):

- a legacy item with `ActionType = "execute"` is force-disabled
  (`Enabled := false`) and counted in the "oude X-acties uitgeschakeld"
  notice;
- a duplicate `Id` (e.g. from hand-edited JSON) gets a freshly generated one;
- missing `Options`/`Enabled` fields fall back to
  `DefaultHotstringOptions()` / `true`.

Any of the above sets `needsMigration := true`, so the file is rewritten
(backup + temp + verify, see `docs/ARCHITECTURE.md` §7.2) even without a
version bump.

**Legacy filenames:** none. Unlike speed dial, there is no alternate
historical filename fallback for hotstrings — only the one-time `DocBot.ini`
+ `hotstrings.json` relocation from the script folder into the user-data
profile at first start (see `README.md`, "Bij de eerste start...").

**Ceiling:** `LoadHotstringsFromJson()` rejects a file whose `schemaVersion`
exceeds `HotstringSchemaVersion`.

---

## Speed dial — `speeddial.json`

`SpeedDialSchemaVersion` (currently **3**). Functional key: `naam`
(case-insensitive) **or** `nummer` (exact) — either match counts as
"already exists".

| Version | What it adds | Gate |
|---|---|---|
| (absent) | Treated as version 1. | — |
| 1 → 2 | `actief` defaults to `true` when the field is missing (older entries had no active/inactive concept). | `!rawEntry.Has("actief")` per entry |
| 3 | Locally configured default speed-dial numbers (`LocalConfig["DefaultSpeedDials"]`) are added once via `AddMissingDefaultSpeedDials()`. A match on name *or* number blocks the add. | `schemaVersion < 3` |

**Legacy filenames:** `InitializeSpeedDialStorage()` checks, in order, for
`speeddial.json` in the user-data profile; if absent, it copies the first
match found among `UserDataDir\snelkiesnummers.json`,
`A_ScriptDir\snelkiesnummers.json`, `A_ScriptDir\speeddial.json` into the
profile once, then runs the normal load/migration path on the copy.

**Ceiling:** `LoadSpeedDialFromJson()` rejects a file whose `schemaVersion`
exceeds `SpeedDialSchemaVersion`.

---

## Bundled package manifest & package files — `packages/manifest.json`, `packages/*.json`

`BundledPackageSchemaVersion` (currently **1**). No version-gated migration
exists yet — the schema has never moved past 1. `InitializeBundledPackages()`
(manifest) and `LoadBundledPackageFile()` (each package) only enforce the
ceiling check via `RejectNewerSchemaVersion()`, plus structural validation
(required fields, duplicate id/trigger detection, `itemCount` consistency).

A manifest entry is a pure `id`/`file` index — nothing else is read from it.
`name`, `version`, `description` and the optional free-text `owner` (who
created/maintains the package) live only in the package file itself; adding
`owner` did not need a schema bump since it is optional and unvalidated
beyond "not an object" (D-054).

These files are not embedded in the application and not user data either:
`InitializeBundledPackages()` reads them live from an external source on
every start — the dev build's own `packages/` directory, or, for the
compiled build, a network share (auto-detected via `A_ScriptDir`, or an
explicit `LocalConfig["Packages"]["ShareDir"]` override) — independent of
`DocBot.exe`'s own build/update cycle (`docs/DECISIONS.md` D-048/D-049).
Editing a package file at that source takes effect at the next DocBot
restart, without a new DocBot build or release. A migration here would only
become relevant if a future DocBot version needs to keep reading an older
bundled-package file format from that source; that need does not exist
today.

---

## Package settings — `package-settings.json`

`PackageSettingsSchemaVersion` (currently **1**). No version-gated migration
exists yet either. Unlike the other three schemas, **every load reconciles
the document unconditionally** via `ReconcilePackageSettings()`, not only
when `schemaVersion < current`:

- `enabledPackages` entries are dropped if the referenced package id no
  longer exists;
- `disabledItems` entries are dropped/pruned against the package's current
  item ids;
- `conflictChoices` entries are dropped unless the referenced custom item,
  package, and package item all still exist *and* the package item's
  trigger/replacement still actually match the custom item (via
  `BuildHotstringIdentity()`);
- the result is saved back with `schemaVersion` set to the current value.

This is deliberate: bundled package *content* can change on every DocBot
update independently of a schema version bump, so stale references need
pruning far more often than a schema migration would fire. Functional key:
`packageId` / `packageItemId` / `customItemId` (all stable ids, never
display names).

**Ceiling:** rejects a file whose `schemaVersion` exceeds
`PackageSettingsSchemaVersion`.

---

## Adding a new migration

When a change needs a new default or a new required field:

1. Bump the relevant `*SchemaVersion` global in `DocBot.ahk`.
2. Gate the one-time behavior with `if schemaVersion < N`, matching the
   pattern already used for hotstrings/speed dial above.
3. Identify existing records by a functional key — never by array index.
4. Never overwrite an existing value for that key.
5. Add a row to the relevant table in this document in the same change.
6. If the new logic is a pure function (no file I/O/GUI/network), add a
   `Test...()` case to `tests/SelfTests.ahk` covering at least: it adds the
   new default once, and a second run doesn't duplicate it.
7. Follow the branch/`AppVersion`/changelog rules in `CLAUDE.md`/`AGENTS.md`.

## Automated coverage

`tests/SelfTests.ahk` (run via `DocBot.ahk --selftest`, see
`tests/README.md`) covers `ReadSchemaVersion()`/`RejectNewerSchemaVersion()`
directly and the idempotency of `AddMissingDefaultHotstrings()` /
`AddMissingDefaultSpeedDials()` / `NormalizeHotstringItem()`. It does not
exercise file I/O, the `.bak`/temp-file write path, GUI refresh, or the
bundled-package/package-settings loaders — those still depend on manual and
compiled Windows validation (`docs/ARCHITECTURE.md` §19, D-037).
