<#
Vraagt de gebruiker interactief om J of N zonder dat Enter nodig is voor
J/N zelf: J of j registreert direct als "ja", N of n direct als "nee".
Enter zonder voorafgaande letter geldt als "ja" (de standaardwaarde).
Andere toetsen worden genegeerd; het script blijft gewoon wachten.
Exitcode 0 = J (of Enter), exitcode 1 = N — dezelfde exitcode-conventie
als tools/Invoke-WithTimeout.ps1.

Wordt bewust via "Get-Content -Raw | Invoke-Expression" aangeroepen, niet
via "-File" en niet via een stdin-pipe zoals tools/Invoke-WithTimeout.ps1:
- "-File" wordt op een beheerde werkplek met een via Group Policy
  afgedwongen AllSigned-beleid geweigerd (zie docs/DECISIONS.md D-060);
- een stdin-pipe (zoals "type bestand.ps1 | powershell -Command -") lost
  dat wel op voor een script zonder interactie, maar [Console]::ReadKey()
  hieronder vereist een niet-omgeleide standaardinvoer en zou daarmee
  meteen een uitzondering geven zodra de scriptinhoud zelf via stdin
  binnenkomt. "Get-Content -Raw | Invoke-Expression" laadt de inhoud via
  een gewone bestandslezing (geen stdin-omleiding) en telt, net als
  "-Command", niet als het laden van een scriptbestand voor het
  uitvoeringsbeleid. Zie docs/DECISIONS.md D-061.

Gebruik (vanuit Build-EPD_Machine.bat):
  set "ASK_PROMPT=Overschrijven met de nieuwste versie? [J/n] "
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Raw 'tools\Read-YesNoAnswer.ps1' | Invoke-Expression"
#>

Write-Host -NoNewline $env:ASK_PROMPT

while ($true) {
    $key = [Console]::ReadKey($true)

    if ($key.Key -eq 'Enter') {
        Write-Host 'J'
        exit 0
    }

    if ($key.KeyChar -eq 'j' -or $key.KeyChar -eq 'J') {
        Write-Host 'J'
        exit 0
    }

    if ($key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
        Write-Host 'N'
        exit 1
    }
}
