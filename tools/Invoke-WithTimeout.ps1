<#
Start een proces, wacht er maximaal INVOKE_WITH_TIMEOUT_MS milliseconden op
en breekt het geforceerd af als het niet binnen die tijd is afgesloten. Dit
bestaat omdat een AutoHotkey v2 GUI-subsysteem-executable (zoals
DocBot.exe) op een blokkerend dialoogvenster kan vastlopen in plaats van
netjes af te sluiten; zie docs/DECISIONS.md D-040. Geeft de exitcode van
het kindproces door zodat de aanroeper (een .bat-bestand kan zelf geen
betrouwbare wait-met-timeout uitvoeren op een synchroon gestart
GUI-subsysteemproces) dezelfde pass/fail-beslissing kan nemen als bij een
normaal afgesloten proces.

Wordt bewust NIET via "powershell -File" aangeroepen en gebruikt daarom
geen param()-blok. Op een beheerde Windows-werkplek met een via Group
Policy afgedwongen AllSigned-/Restricted-uitvoeringsbeleid weigert Windows
een los, ongetekend .ps1-bestand ("... is not digitally signed. You
cannot run this script on the current system.") en negeert het daarbij
ook "-ExecutionPolicy Bypass" — een Group Policy-ingesteld beleid heeft
altijd voorrang op dat opstartargument, in elke scope (zie
docs/DECISIONS.md D-060). Dat beleid geldt alleen voor het laden van
scriptbestanden, niet voor commando's die via "-Command"/stdin worden
aangeleverd. Daarom wordt de inhoud van dit bestand via stdin naar
"powershell -Command -" gepiped in plaats van als scriptbestand te worden
uitgevoerd; parameters komen binnen via omgevingsvariabelen, omdat
positieargumenten op een via stdin aangeleverd commando niet aan een
param()-blok worden gebonden.

Gebruik (vanuit Build-EPD_Machine.bat):
  set "INVOKE_WITH_TIMEOUT_FILEPATH=DocBot.exe"
  set "INVOKE_WITH_TIMEOUT_ARGS=--selftest"
  set "INVOKE_WITH_TIMEOUT_MS=60000"
  type tools\Invoke-WithTimeout.ps1 | powershell -NoProfile -ExecutionPolicy Bypass -Command -
#>

$ErrorActionPreference = 'Stop'

$filePath = $env:INVOKE_WITH_TIMEOUT_FILEPATH
$timeoutMs = [int]$env:INVOKE_WITH_TIMEOUT_MS
$argumentList = @()
if ($env:INVOKE_WITH_TIMEOUT_ARGS) {
    $argumentList = $env:INVOKE_WITH_TIMEOUT_ARGS -split ' '
}

$proc = Start-Process -FilePath $filePath -ArgumentList $argumentList -PassThru -NoNewWindow
$finished = $proc.WaitForExit($timeoutMs)

if (-not $finished) {
    $timeoutSeconds = [int]($timeoutMs / 1000)
    Write-Host "Proces '$filePath' reageerde niet binnen $timeoutSeconds seconden (waarschijnlijk een blokkerend dialoogvenster). Proces wordt afgebroken."
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

exit $proc.ExitCode
