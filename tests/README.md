# DocBot — zelftests

Dit is geen conventionele testsuite met een los testrunner-framework. DocBot
is één groot, monolithisch AutoHotkey v2-script met een strikte
top-level-uitvoeringsvolgorde (zie `docs/ARCHITECTURE.md` §3); losse unit
tests die `DocBot.ahk` `#Include`'n zouden de volledige auto-execute-sectie
(lokale configuratie, GUI-opbouw, telefonie, telemetrie) meestarten. In
plaats daarvan bevat DocBot zelf een verborgen, expliciet opt-in testpoort.

## Wat hier getest wordt

`SelfTests.ahk` bevat alleen functiedefinities en test uitsluitend pure
logica zonder bestands-I/O, GUI of netwerk:

- `ReadSchemaVersion()` / `RejectNewerSchemaVersion()` — de gedeelde
  schemaVersion-bouwstenen die alle vier de opslagformaten gebruiken;
- idempotentie van `AddMissingDefaultHotstrings()` en
  `AddMissingDefaultSpeedDials()` — een tweede aanroep op dezelfde lijst
  voegt niets dubbel toe, en een bestaande afkorting/naam/nummer wordt niet
  overschreven;
- normalisatiegedrag van `NormalizeHotstringItem()`, inclusief het
  uitschakelen van oude `ActionType=execute`-items.

Zie `docs/MIGRATIONS.md` voor het volledige migratieoverzicht per
opslagformaat en de betekenis van "idempotent" in deze context.

**Niet gedekt:** de bestands-I/O, `.bak`/tijdelijk-bestand-schrijfpaden,
GUI-vernieuwing of `showMessage`-dialogen van
`LoadHotstringsFromJson()`/`LoadSpeedDialFromJson()`/
`LoadPackageSettingsFromJson()`/`InitializeBundledPackages()` zelf, en niets
van telefonie, SMS/UIA, telemetrie of diagnostiek. Dit blijft, zoals de rest
van DocBot, afhankelijk van handmatige en gecompileerde Windows-validatie
(zie `docs/ARCHITECTURE.md` §19, D-037).

## Lokaal uitvoeren (Windows, AutoHotkey v2 geïnstalleerd)

```powershell
copy DocBot.local.example.ahk DocBot.local.ahk
AutoHotkey64.exe DocBot.ahk --selftest
```

Dit vereist een geldige lokale configuratie (de voorbeeldconfiguratie
volstaat) omdat de testpoort pas ná `ValidateLocalConfiguration()` in
`DocBot.ahk` wordt bereikt — precies zoals een normale start. Zonder
argumenten start `DocBot.ahk` gewoon de volledige applicatie; deze testpoort
wordt dan nooit bereikt.

De resultaten (per test een `ok`- of `FAIL`-regel plus een samenvattingsregel)
worden weggeschreven naar `%TEMP%\docbot-selftest-results.txt` (bij elke run
overschreven) en, best-effort, ook naar stdout. Het resultatenbestand is de
betrouwbare uitvoer: `AutoHotkey64.exe` is een GUI-subsysteem-executable, en
of `FileAppend(tekst, "*")` stdout daadwerkelijk bereikt wanneer dat wordt
omgeleid, is nergens anders in deze codebase bevestigd (zie
`docs/DECISIONS.md` D-053). Het proces sluit in beide gevallen af met
exitcode `0` bij een volledig geslaagde run en `1` zodra één test faalt of
onverwacht een fout werpt — dat is het gezaghebbende signaal, niet de
logtekst.

## In CI

`.github/workflows/ahk-syntax-check.yml` voert dit na de bestaande
`/Validate`-syntaxcontrole uit als extra stap in dezelfde job, met dezelfde
`WaitForExit`/force-kill-aanpak als de syntaxcontrole (zie
`docs/DECISIONS.md` D-040) omdat een AutoHotkey-proces ook hier op een
blokkerend dialoogvenster kan vastlopen in plaats van netjes af te sluiten.
Na `WaitForExit` leest de stap `%TEMP%\docbot-selftest-results.txt` voor de
leesbare CI-log en gebruikt de procesexitcode voor slagen/falen; ontbreekt
het logbestand, dan toont de stap alleen een waarschuwing in plaats van te
falen — het echte resultaat blijft de exitcode.

## Bij het compileren (`Build-EPD_Machine.bat`)

`Build-EPD_Machine.bat` draait, direct na een geslaagde compilatie en vóór
enige `:deploy`-aanroep, `--selftest` tegen de zojuist gecompileerde
`DocBot.exe` zelf — niet tegen een reeds uitgerolde doelkopie en niet tegen
het interpreteerde bronscript. Dit is dezelfde controle als bij de eerdere
handmatige verificatie tijdens de 2.3-release (D-053), nu geautomatiseerd.

Omdat `cmd.exe` een GUI-subsysteem-executable niet vanzelf synchroon afwacht
zoals bij een console-executable, en omdat een blokkerend dialoogvenster de
batch anders voor onbepaalde tijd zou laten hangen, gebruikt de batch
hiervoor `tools/Invoke-WithTimeout.ps1` — een klein PowerShell-hulpscript dat
hetzelfde `Start-Process`/`WaitForExit`/`Stop-Process -Force`-patroon
toepast als de CI-stap hierboven (zestig seconden timeout, daarna geforceerd
afbreken) en de exitcode van het kindproces doorgeeft. De batch toont
`%TEMP%\docbot-selftest-results.txt` in de console ongeacht het resultaat en
breekt af zonder iets uit te rollen zodra de exitcode niet `0` is (inclusief
een time-out) of het logbestand ontbreekt met een waarschuwing in plaats van
een harde fout, op dezelfde manier als de CI-stap.

De CI-workflow zelf gebruikt dit hulpscript vooralsnog niet en blijft zijn
eigen, functioneel identieke `pwsh`-fragment gebruiken.

## Een nieuwe test toevoegen

Voeg een nieuwe `Test...(results)`-functie toe in `SelfTests.ahk`, roep
`AssertEqual()`/`AssertTrue()` aan, en registreer de functie in
`RunSelfTests()`. Test alleen functies die geen globale UI-/netwerktoestand
aanraken; als een functie dat wel doet, hoort de test hier niet thuis en is
handmatige/gecompileerde Windows-validatie het juiste instrument (zie
`docs/PROJECT_CONTEXT.md` §8).
