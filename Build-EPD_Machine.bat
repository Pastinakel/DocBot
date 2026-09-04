@echo off
setlocal EnableExtensions
rem Dit bestand moet CRLF-regeleindes behouden (afgedwongen via
rem .gitattributes). cmd.exe kan met LF-regeleindes onbetrouwbaar zijn
rem bij het vinden van GOTO/CALL-labels verderop in het bestand ("The
rem system cannot find the batch label specified"), zie docs/DECISIONS.md
rem D-057.

rem Werk altijd vanuit de map waarin dit batchbestand staat.
cd /d "%~dp0"

set "AHK2EXE=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set "SOURCE=%~dp0DocBot.ahk"
set "OUTPUT=%~dp0DocBot.exe"
set "ICON=%~dp0images\DocBot.ico"
set "BASE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"

rem De uitvoernaam wordt afgeleid van de bovenliggende applicatiemap.
rem De gecompileerde DocBot.exe blijft in de bronmap; de kopie erboven krijgt
rem de naam van die applicatiemap.
for %%I in ("%~dp0..") do set "PARENT_DIR=%%~fI"
for %%I in ("%PARENT_DIR%") do set "APP_NAME=%%~nxI"
for %%I in ("%PARENT_DIR%\..") do set "ROOT_DIR=%%~fI"
set "TARGET=%PARENT_DIR%\%APP_NAME%.exe"

if not exist "%AHK2EXE%" (
    echo FOUT: Ahk2Exe.exe is niet gevonden:
    echo "%AHK2EXE%"
    goto :failed
)

if not exist "%SOURCE%" (
    echo FOUT: Het bronscript is niet gevonden:
    echo "%SOURCE%"
    goto :failed
)

if not exist "%ICON%" (
    echo FOUT: Het pictogrambestand is niet gevonden:
    echo "%ICON%"
    goto :failed
)

if not exist "%BASE%" (
    echo FOUT: AutoHotkey64.exe is niet gevonden:
    echo "%BASE%"
    goto :failed
)

rem ============================================================
rem  Alle vragen worden hier vooraf gesteld, voordat het compileren
rem  begint. Daarna doorloopt het script alle stappen zonder verdere
rem  onderbrekingen. Op Enter (zonder tekst intypen) wordt telkens
rem  Ja (J) geregistreerd; alleen een expliciete "N" telt als Nee.
rem ============================================================

rem Alleen de centrale developversie of een RC mag vanaf een directe submap
rem van DocBot optioneel ook naar de naastgelegen applicatiemap EPD_Machine
rem worden uitgerold.
set "IS_DEVELOP="
findstr /B /C:"global AppVersion" "%SOURCE%" | findstr /C:"-dev" /C:"-rc" >nul
if not errorlevel 1 set "IS_DEVELOP=1"

set "DO_EPD_COPY="
if defined IS_DEVELOP if /I "%APP_NAME%"=="DocBot" (
    if not exist "%ROOT_DIR%\EPD_Machine\" (
        echo De naastgelegen applicatiemap EPD_Machine bestaat niet; deze
        echo stap wordt overgeslagen:
        echo "%ROOT_DIR%\EPD_Machine"
    ) else (
        call :ask "Ook een executable naar de naastgelegen map EPD_Machine kopieren? [J/n] " DO_EPD_COPY
    )
)

set "OVERWRITE_MAIN_PACKAGES=J"
if exist "%PARENT_DIR%\packages\" (
    echo.
    echo Er staat al een pakketmap in de doellocatie:
    echo "%PARENT_DIR%\packages"
    call :ask "Overschrijven met de nieuwste versie uit deze checkout? [J/n] " OVERWRITE_MAIN_PACKAGES
)

set "OVERWRITE_EPD_PACKAGES=J"
if /I "%DO_EPD_COPY%"=="J" if exist "%ROOT_DIR%\EPD_Machine\packages\" (
    echo.
    echo Er staat al een pakketmap in de doellocatie:
    echo "%ROOT_DIR%\EPD_Machine\packages"
    call :ask "Overschrijven met de nieuwste versie uit deze checkout? [J/n] " OVERWRITE_EPD_PACKAGES
)

echo.
echo Alle vragen zijn beantwoord. Het compileren en uitrollen start nu
echo en loopt door zonder verdere onderbrekingen.
echo.

echo DocBot compileren naar DocBot.exe...
"%AHK2EXE%" /in "%SOURCE%" /out "%OUTPUT%" /icon "%ICON%" /base "%BASE%" /compress 0

if errorlevel 1 (
    echo.
    echo FOUT: Compileren is mislukt.
    goto :failed
)

echo.
echo Build gereed:
echo "%OUTPUT%"
echo.

echo Zelftest uitvoeren tegen de zojuist gecompileerde DocBot.exe...
set "SELFTEST_LOG=%TEMP%\docbot-selftest-results.txt"
if exist "%SELFTEST_LOG%" del /f /q "%SELFTEST_LOG%" >nul 2>&1

rem Een AutoHotkey v2 GUI-subsysteem-executable kan op een blokkerend
rem dialoogvenster vastlopen in plaats van netjes af te sluiten, en
rem cmd.exe wacht sowieso niet vanzelf op een GUI-subsysteemproces zoals
rem het wel op een console-executable zou doen. Daarom draait de zelftest
rem via tools\Invoke-WithTimeout.ps1, dat dezelfde WaitForExit/force-kill-
rem aanpak gebruikt als de CI-workflow (docs/DECISIONS.md D-040).
rem De inhoud wordt via stdin naar "powershell -Command -" gepiped in
rem plaats van met "-File" te worden uitgevoerd: op een beheerde werkplek
rem met een via Group Policy afgedwongen AllSigned-beleid weigert Windows
rem een los, ongetekend .ps1-bestand en negeert het daarbij ook
rem "-ExecutionPolicy Bypass", omdat een Group Policy-ingesteld beleid
rem altijd voorrang heeft op dat opstartargument. Dat beleid geldt alleen
rem voor het laden van scriptbestanden, niet voor commando's die via
rem stdin binnenkomen (zie docs/DECISIONS.md D-060).
set "INVOKE_WITH_TIMEOUT_FILEPATH=%OUTPUT%"
set "INVOKE_WITH_TIMEOUT_ARGS=--selftest"
set "INVOKE_WITH_TIMEOUT_MS=60000"
type "%~dp0tools\Invoke-WithTimeout.ps1" | powershell -NoProfile -ExecutionPolicy Bypass -Command -
set "SELFTEST_RESULT=%errorlevel%"
set "INVOKE_WITH_TIMEOUT_FILEPATH="
set "INVOKE_WITH_TIMEOUT_ARGS="
set "INVOKE_WITH_TIMEOUT_MS="

rem Het resultatenbestand is de betrouwbare uitvoer, niet de console
rem (zie docs/DECISIONS.md D-053); toon het ongeacht het gemeten resultaat.
if exist "%SELFTEST_LOG%" (
    type "%SELFTEST_LOG%"
) else (
    echo Waarschuwing: "%SELFTEST_LOG%" niet gevonden; zie tests/README.md.
)

if not "%SELFTEST_RESULT%"=="0" (
    echo.
    echo FOUT: Zelftest tegen de gecompileerde DocBot.exe is mislukt ^(exit %SELFTEST_RESULT%^).
    echo Er is niets uitgerold naar de doelmap of doelmappen.
    goto :failed
)

echo Zelftest geslaagd.
echo.

call :deploy "%TARGET%" "%APP_NAME%" "%OVERWRITE_MAIN_PACKAGES%"
if errorlevel 1 goto :failed

if /I "%DO_EPD_COPY%"=="J" (
    rem ROOT_DIR is al buiten dit haakjesblok gezet. Gebruik het pad
    rem rechtstreeks: een variabele die binnen hetzelfde blok wordt gezet,
    rem wordt met %%...%% mogelijk te vroeg geexpandeerd.
    call :deploy "%ROOT_DIR%\EPD_Machine\EPD_Machine.exe" "EPD_Machine" "%OVERWRITE_EPD_PACKAGES%"
    if errorlevel 1 goto :failed
)

:done
echo.
echo Alle gekozen kopieeracties zijn voltooid.
echo.
pause
exit /b 0

rem Stelt een J/n-vraag. J of j registreert direct als Ja, N of n direct
rem als Nee (geen Enter nodig); Enter zonder voorafgaande letter geldt als
rem Ja. Gebruikt tools\Read-YesNoAnswer.ps1 (Get-Content/Invoke-Expression
rem i.p.v. -File of een stdin-pipe; zie docs/DECISIONS.md D-060/D-061).
rem %1 = prompttekst, %2 = naam van de variabele die J of N krijgt.
:ask
setlocal EnableExtensions
set "ASK_PROMPT=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Raw '%~dp0tools\Read-YesNoAnswer.ps1' | Invoke-Expression"
if errorlevel 1 (set "ASK_RESULT=N") else set "ASK_RESULT=J"
endlocal & set "%~2=%ASK_RESULT%"
exit /b 0

:deploy
setlocal EnableExtensions
set "DEPLOY_TARGET=%~1"
set "DEPLOY_NAME=%~2"
set "DEPLOY_OVERWRITE_PACKAGES=%~3"
for %%I in ("%DEPLOY_TARGET%") do set "DEPLOY_DIR=%%~dpI"
set "DEPLOY_SIGNAL=%DEPLOY_DIR%signal.txt"
set "DEPLOY_RESULT=0"

echo Updatesignaal plaatsen:
echo "%DEPLOY_SIGNAL%"
call :signal_add "%DEPLOY_SIGNAL%" "ALL:update"
if errorlevel 1 (
    echo.
    echo FOUT: ALL:update kon niet aan signal.txt worden toegevoegd.
    echo Er is niets naar deze doelmap gekopieerd.
    endlocal & exit /b 1
)

if exist "%DEPLOY_TARGET%" (
    echo In de doelmap staat al een %DEPLOY_NAME%.exe.
    echo Actieve DocBot-clients krijgen maximaal 25 seconden om af te sluiten...
)

set /a "WAITED_SECONDS=0"

:deploy_try_install
rem Een actieve executable kan na DEL al als niet-bestaand worden gemeld,
rem terwijl Windows hem nog in delete-pending toestand vasthoudt. Probeer
rem daarom niet alleen verwijderen, maar ook kopieren en verifieren opnieuw.
if exist "%DEPLOY_TARGET%" del /f /q "%DEPLOY_TARGET%" >nul 2>&1
if exist "%DEPLOY_TARGET%" goto :deploy_wait

copy /y "%OUTPUT%" "%DEPLOY_TARGET%" >nul 2>&1
if errorlevel 1 goto :deploy_wait

rem COPY met exitcode 0 is niet genoeg bewijs bij een netwerkpad.
rem De uitrol is pas klaar als bron en doel byte-voor-byte gelijk zijn.
fc /b "%OUTPUT%" "%DEPLOY_TARGET%" >nul 2>&1
if errorlevel 1 goto :deploy_wait

echo Nieuwe executable geplaatst en geverifieerd:
echo "%DEPLOY_TARGET%"

call :sync_packages "%DEPLOY_DIR%" "%DEPLOY_OVERWRITE_PACKAGES%"
if errorlevel 1 set "DEPLOY_RESULT=1"

goto :deploy_cleanup

:deploy_wait
if %WAITED_SECONDS% GEQ 25 goto :deploy_locked

timeout /t 1 /nobreak >nul
set /a "WAITED_SECONDS+=1"
goto :deploy_try_install

:deploy_locked
echo.
echo FOUT: Het doelbestand kon na 25 seconden nog niet worden vervangen:
echo "%DEPLOY_TARGET%"
echo Mogelijk gebruikt een DocBot-client de oude executable nog.
set "DEPLOY_RESULT=1"
goto :deploy_cleanup

:deploy_cleanup
call :signal_remove "%DEPLOY_SIGNAL%" "ALL:update"
if errorlevel 1 (
    echo.
    echo FOUT: ALL:update kon niet uit signal.txt worden verwijderd:
    echo "%DEPLOY_SIGNAL%"
    echo Verwijder deze regel handmatig voordat DocBot opnieuw wordt gestart.
    set "DEPLOY_RESULT=1"
) else (
    echo Updatesignaal verwijderd; afgesloten clients mogen opnieuw starten.
)

endlocal & exit /b %DEPLOY_RESULT%

rem De gecompileerde DocBot.exe leidt haar pakketbron bij ontbreken van een
rem expliciete Packages.ShareDir-override automatisch af uit A_ScriptDir
rem (docs/DECISIONS.md D-049), oftewel een map "packages" naast zichzelf. Op
rem een verse doellocatie bestaat die submap nog niet; deze stap zorgt dat
rem elke deploy-map er een krijgt, zonder een reeds aanwezige (mogelijk met
rem lokaal toegevoegde pakketten) stilzwijgend te overschrijven. Of een
rem bestaande pakketmap mag worden overschreven, is al vooraf beantwoord
rem via de OVERWRITE_*_PACKAGES-vraag; hier wordt niet opnieuw gevraagd.
:sync_packages
setlocal EnableExtensions
set "SYNC_SOURCE=%~dp0packages"
set "SYNC_DEST=%~1packages"
set "SYNC_OVERWRITE=%~2"

if not exist "%SYNC_SOURCE%\" (
    echo.
    echo FOUT: De bronmap packages is niet gevonden:
    echo "%SYNC_SOURCE%"
    endlocal & exit /b 1
)

if not exist "%SYNC_DEST%\" (
    echo Geen pakketmap aangetroffen; wordt gevuld vanuit deze checkout:
    echo "%SYNC_DEST%"
    xcopy "%SYNC_SOURCE%" "%SYNC_DEST%\" /E /I /Y >nul
    if errorlevel 1 (
        echo.
        echo FOUT: Pakketmap kon niet worden aangemaakt/gevuld.
        endlocal & exit /b 1
    )
    echo Pakketmap aangemaakt en gevuld.
    endlocal & exit /b 0
)

if /I not "%SYNC_OVERWRITE%"=="J" (
    echo Bestaande pakketmap ongewijzigd gelaten.
    endlocal & exit /b 0
)

rem Volledig vervangen, niet samenvoegen: een pakketbestand dat hier is
rem verwijderd of hernoemd moet ook echt verdwijnen in de doelmap, niet
rem naast de nieuwe set blijven hangen.
rd /s /q "%SYNC_DEST%" >nul 2>&1
xcopy "%SYNC_SOURCE%" "%SYNC_DEST%\" /E /I /Y >nul
if errorlevel 1 (
    echo.
    echo FOUT: Pakketmap kon niet worden vervangen.
    endlocal & exit /b 1
)

echo Pakketmap vervangen met de nieuwste versie.
endlocal & exit /b 0

:signal_add
set "DEPLOY_SIGNAL_FILE=%~1"
set "DEPLOY_SIGNAL_COMMAND=%~2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p=$env:DEPLOY_SIGNAL_FILE; $command=$env:DEPLOY_SIGNAL_COMMAND; $utf8=New-Object System.Text.UTF8Encoding -ArgumentList $false; $lines=if ([IO.File]::Exists($p)) { [IO.File]::ReadAllLines($p) } else { @() }; $lines=@($lines | Where-Object { $_.Trim() -ine $command }); $lines+=$command; [IO.File]::WriteAllLines($p,$lines,$utf8) } catch { Write-Error $_; exit 1 }"
exit /b %errorlevel%

:signal_remove
set "DEPLOY_SIGNAL_FILE=%~1"
set "DEPLOY_SIGNAL_COMMAND=%~2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "try { $p=$env:DEPLOY_SIGNAL_FILE; $command=$env:DEPLOY_SIGNAL_COMMAND; if (![IO.File]::Exists($p)) { exit 0 }; $utf8=New-Object System.Text.UTF8Encoding -ArgumentList $false; $lines=@([IO.File]::ReadAllLines($p) | Where-Object { $_.Trim() -ine $command }); [IO.File]::WriteAllLines($p,$lines,$utf8) } catch { Write-Error $_; exit 1 }"
exit /b %errorlevel%

:failed
echo.
pause
exit /b 1
