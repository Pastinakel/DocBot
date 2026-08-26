<#
Start een proces, wacht er maximaal TimeoutMs op en breekt het geforceerd af
als het niet binnen die tijd is afgesloten. Dit bestaat omdat een
AutoHotkey v2 GUI-subsysteem-executable (zoals DocBot.exe) op een
blokkerend dialoogvenster kan vastlopen in plaats van netjes af te sluiten;
zie docs/DECISIONS.md D-040. Geeft de exitcode van het kindproces door zodat
de aanroeper (een .bat-bestand kan zelf geen betrouwbare wait-met-timeout
uitvoeren op een synchroon gestart GUI-subsysteemproces) dezelfde
pass/fail-beslissing kan nemen als bij een normaal afgesloten proces.

Gebruik (vanuit Build-EPD_Machine.bat):
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Invoke-WithTimeout.ps1 -FilePath "DocBot.exe" -ArgumentList "--selftest" -TimeoutMs 60000
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter()]
    [string[]]$ArgumentList = @(),

    [Parameter()]
    [int]$TimeoutMs = 60000
)

$ErrorActionPreference = 'Stop'

$proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -NoNewWindow
$finished = $proc.WaitForExit($TimeoutMs)

if (-not $finished) {
    $timeoutSeconds = [int]($TimeoutMs / 1000)
    Write-Host "Proces '$FilePath' reageerde niet binnen $timeoutSeconds seconden (waarschijnlijk een blokkerend dialoogvenster). Proces wordt afgebroken."
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

exit $proc.ExitCode
