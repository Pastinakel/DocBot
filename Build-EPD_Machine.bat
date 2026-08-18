@echo off
setlocal EnableExtensions

rem Werk altijd vanuit de map waarin dit batchbestand staat.
cd /d "%~dp0"

set "AHK2EXE=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set "SOURCE=%~dp0DocBot.ahk"
set "OUTPUT=%~dp0DocBot.exe"
set "ICON=%~dp0DocBot.ico"
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

call :deploy "%TARGET%" "%APP_NAME%"
if errorlevel 1 goto :failed

rem Alleen de centrale developversie of een RC mag vanaf een directe submap van DocBot
rem optioneel ook naar de naastgelegen applicatiemap worden uitgerold.
set "IS_DEVELOP="
findstr /B /C:"global AppVersion" "%SOURCE%" | findstr /C:"-dev" /C:"-rc" >nul
if not errorlevel 1 set "IS_DEVELOP=1"

if defined IS_DEVELOP if /I "%APP_NAME%"=="DocBot" (
    echo.
    choice /C JN /N /M "Ook een executable naar de naastgelegen map EPD_Machine kopieren? [J/N] "
    if errorlevel 2 goto :done

    if not exist "%ROOT_DIR%\EPD_Machine\" (
        echo.
        echo FOUT: De naastgelegen applicatiemap bestaat niet:
        echo "%ROOT_DIR%\EPD_Machine"
        goto :failed
    )

    rem ROOT_DIR is al buiten dit haakjesblok gezet. Gebruik het pad
    rem rechtstreeks: een variabele die binnen hetzelfde blok wordt gezet,
    rem wordt met %%...%% mogelijk te vroeg geexpandeerd.
    call :deploy "%ROOT_DIR%\EPD_Machine\EPD_Machine.exe" "EPD_Machine"
    if errorlevel 1 goto :failed
)

:done
echo.
echo Alle gekozen kopieeracties zijn voltooid.
echo.
pause
exit /b 0

:deploy
setlocal EnableExtensions
set "DEPLOY_TARGET=%~1"
set "DEPLOY_NAME=%~2"
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

call :sync_packages "%DEPLOY_DIR%"
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
rem lokaal toegevoegde pakketten) stilzwijgend te overschrijven.
:sync_packages
setlocal EnableExtensions
set "SYNC_SOURCE=%~dp0packages"
set "SYNC_DEST=%~1packages"

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

echo.
echo Er staat al een pakketmap in de doellocatie:
echo "%SYNC_DEST%"
choice /C JN /N /M "Overschrijven met de nieuwste versie uit deze checkout? [J/N] "
if errorlevel 2 (
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
