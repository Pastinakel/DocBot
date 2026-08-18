; DocBot — losstaand zelftestpakket voor schema-migratielogica.
;
; Bevat alleen functiedefinities; deze regels voeren niets uit tijdens een
; normale start. Ze worden pas aangeroepen via de --selftest-poort direct
; ná ValidateLocalConfiguration() in DocBot.ahk (vóór AppVersion, vóór elke
; GUI-, gebruikersdata- of netwerktoegang), en alleen wanneer DocBot met dat
; expliciete argument wordt gestart. Een dubbelklik op de gecompileerde
; executable of een normale ontwikkelstart bereikt deze code nooit.
;
; Getest wordt uitsluitend pure logica die geen bestands-I/O, GUI of
; netwerk aanraakt: het lezen/afwijzen van schemaVersion-waarden
; (ReadSchemaVersion / RejectNewerSchemaVersion, gedefinieerd vlak vóór
; InitializeBundledPackages() in DocBot.ahk) en de idempotentie van de
; eenmalige standaardwaarde-migraties voor persoonlijke hotstrings en
; snelkiesnummers (AddMissingDefaultHotstrings / AddMissingDefaultSpeedDials).
; Dit dekt bewust niet de bestands-I/O, GUI-vernieuwing of showMessage-paden
; van LoadHotstringsFromJson/LoadSpeedDialFromJson zelf.
;
; "Idempotent" betekent hier alleen: een tweede aanroep op dezelfde lijst
; voegt niets dubbel toe. Dat een eenmaal door de gebruiker verwijderde
; standaardwaarde niet vanzelf terugkomt, is geen eigenschap van deze
; functies maar van de aanroepende migratiepoort (`if schemaVersion < N`)
; die ze maar één keer per bestand aanroept — zie docs/DECISIONS.md D-010
; en docs/MIGRATIONS.md.
;
; Zie tests/README.md voor hoe dit pakket lokaal en in CI wordt uitgevoerd.

RunSelfTests() {
    results := SelfTestResults()

    RunSelfTestCase(results, "TestReadSchemaVersion", TestReadSchemaVersion)
    RunSelfTestCase(results, "TestRejectNewerSchemaVersion", TestRejectNewerSchemaVersion)
    RunSelfTestCase(results, "TestNormalizeHotstringItemIdempotency", TestNormalizeHotstringItemIdempotency)
    RunSelfTestCase(results, "TestAddMissingDefaultHotstringsIdempotency", TestAddMissingDefaultHotstringsIdempotency)
    RunSelfTestCase(results, "TestAddMissingDefaultSpeedDialsIdempotency", TestAddMissingDefaultSpeedDialsIdempotency)
    RunSelfTestCase(results, "TestCreateSpeedDialEntryDefaults", TestCreateSpeedDialEntryDefaults)

    logText := ""
    for _, line in results["lines"]
        logText .= line "`n"
    logText .= Format(
        "`n{1} test(s), {2} geslaagd, {3} mislukt.`n",
        results["total"],
        results["passed"],
        results["total"] - results["passed"]
    )

    ; AutoHotkey64.exe is een GUI-subsysteem-executable; of FileAppend(...,
    ; "*") daadwerkelijk naar een omgeleide stdout schrijft is (nog) niet op
    ; Windows bevestigd (zie docs/DECISIONS.md D-053). Het resultatenbestand
    ; in %TEMP% is daarom de primaire, betrouwbaardere uitvoer — net als de
    ; bestaande tijdelijke diagnostiekbestanden (D-041/D-044). Schrijffouten
    ; naar beide mogen de exitcode nooit beïnvloeden; die weerspiegelt
    ; uitsluitend het echte testresultaat.
    logPath := SelfTestLogPath()
    if FileExist(logPath)
        try FileDelete(logPath)
    try FileAppend(logText, logPath, "UTF-8")
    try FileAppend(logText, "*")

    return results["passed"] = results["total"] ? 0 : 1
}

; %TEMP%\docbot-selftest-results.txt — leesbaar door de CI-stap ná
; WaitForExit, ongeacht of stdout-omleiding voor dit GUI-subsysteemproces
; werkt. Wordt bij elke --selftest-run overschreven, niet aangevuld.
SelfTestLogPath() {
    return A_Temp "\docbot-selftest-results.txt"
}

SelfTestResults() {
    return Map("total", 0, "passed", 0, "lines", [])
}

; Vangt een onverwachte fout in één testfunctie op, zodat die als een
; duidelijke FAIL-regel wordt gerapporteerd in plaats van het hele
; --selftest-proces te laten crashen op een blokkerend Windows-
; foutdialoogvenster (dezelfde klasse risico als D-040 voor /Validate).
RunSelfTestCase(results, name, testFn) {
    try
        testFn(results)
    catch as testError {
        results["total"] += 1
        results["lines"].Push(
            Format("FAIL  - {1} wierp een onverwachte fout: {2}", name, testError.Message)
        )
    }
}

AssertEqual(results, label, actual, expected) {
    results["total"] += 1
    if actual = expected {
        results["passed"] += 1
        results["lines"].Push("ok    - " label)
    } else {
        results["lines"].Push(
            Format("FAIL  - {1} (verwacht '{2}', gekregen '{3}')", label, expected, actual)
        )
    }
}

AssertTrue(results, label, condition) {
    AssertEqual(results, label, condition ? 1 : 0, 1)
}

TestReadSchemaVersion(results) {
    AssertEqual(results, "ReadSchemaVersion valt terug op 1 zonder het veld", ReadSchemaVersion(Map()), 1)
    AssertEqual(results, "ReadSchemaVersion leest een numerieke waarde", ReadSchemaVersion(Map("schemaVersion", 3)), 3)
    AssertEqual(
        results,
        "ReadSchemaVersion dwingt een tekstwaarde af naar een getal",
        ReadSchemaVersion(Map("schemaVersion", "4")),
        4
    )
}

TestRejectNewerSchemaVersion(results) {
    threw := false
    try
        RejectNewerSchemaVersion(3, 5, "Test")
    catch
        threw := true
    AssertTrue(results, "RejectNewerSchemaVersion staat een gelijke/oudere versie toe", !threw)

    threw := false
    try
        RejectNewerSchemaVersion(5, 5, "Test")
    catch
        threw := true
    AssertTrue(results, "RejectNewerSchemaVersion staat exact de huidige versie toe", !threw)

    threw := false
    try
        RejectNewerSchemaVersion(6, 5, "Test")
    catch
        threw := true
    AssertTrue(results, "RejectNewerSchemaVersion wijst een nieuwere versie af", threw)
}

TestNormalizeHotstringItemIdempotency(results) {
    raw := Map("Trigger", "xtest", "Replacement", "Testvervanging")
    first := NormalizeHotstringItem(raw)
    AssertTrue(results, "NormalizeHotstringItem kent een Id toe wanneer die ontbreekt", Trim(first["Id"]) != "")
    AssertEqual(
        results,
        "NormalizeHotstringItem gebruikt Origin.Type=custom bij een ontbrekende Origin",
        first["Origin"]["Type"],
        "custom"
    )

    second := NormalizeHotstringItem(first)
    AssertEqual(results, "NormalizeHotstringItem is idempotent voor een genormaliseerd item (Id)", second["Id"], first["Id"])
    AssertEqual(
        results,
        "NormalizeHotstringItem is idempotent voor een genormaliseerd item (Trigger)",
        second["Trigger"],
        first["Trigger"]
    )
    AssertEqual(
        results,
        "NormalizeHotstringItem is idempotent voor een genormaliseerd item (Enabled)",
        second["Enabled"],
        first["Enabled"]
    )

    legacy := Map("Trigger", "xoud", "Replacement", "Oude actie", "ActionType", "execute")
    normalizedLegacy := NormalizeHotstringItem(legacy)
    AssertEqual(
        results,
        "NormalizeHotstringItem schakelt een oude ActionType=execute uit",
        normalizedLegacy["Enabled"],
        false
    )
}

TestAddMissingDefaultHotstringsIdempotency(results) {
    global LocalConfig
    originalConfig := LocalConfig
    LocalConfig := Map(
        "DefaultHotstrings", [
            Map("Trigger", "zt1", "Replacement", "Zelftestvervanging 1"),
            Map("Trigger", "zt2", "Replacement", "Zelftestvervanging 2")
        ]
    )

    try {
        items := []
        firstAdded := AddMissingDefaultHotstrings(items)
        AssertEqual(results, "AddMissingDefaultHotstrings voegt alle ontbrekende standaarditems toe", firstAdded, 2)
        AssertEqual(results, "AddMissingDefaultHotstrings vult de lijst aan tot de verwachte lengte", items.Length, 2)

        secondAdded := AddMissingDefaultHotstrings(items)
        AssertEqual(results, "AddMissingDefaultHotstrings voegt bij een tweede aanroep niets dubbel toe", secondAdded, 0)
        AssertEqual(results, "AddMissingDefaultHotstrings laat de lijstlengte ongewijzigd bij herhaling", items.Length, 2)

        itemsWithExisting := [
            CreateHotstringItem("ZT1", "Eigen vervanging", "", true, DefaultHotstringOptions(), "")
        ]
        addedWithExisting := AddMissingDefaultHotstrings(itemsWithExisting)
        AssertEqual(
            results,
            "AddMissingDefaultHotstrings herkent een bestaande afkorting hoofdletterongevoelig",
            addedWithExisting,
            1
        )
        AssertEqual(
            results,
            "AddMissingDefaultHotstrings overschrijft een bestaande afkorting niet",
            itemsWithExisting[1]["Replacement"],
            "Eigen vervanging"
        )
    } finally {
        LocalConfig := originalConfig
    }
}

TestAddMissingDefaultSpeedDialsIdempotency(results) {
    global LocalConfig
    originalConfig := LocalConfig
    LocalConfig := Map(
        "DefaultSpeedDials", [
            Map("Name", "Zelftest Een", "Number", "1111"),
            Map("Name", "Zelftest Twee", "Number", "2222")
        ]
    )

    try {
        entries := []
        firstAdded := AddMissingDefaultSpeedDials(entries)
        AssertEqual(results, "AddMissingDefaultSpeedDials voegt alle ontbrekende standaardnummers toe", firstAdded, 2)

        secondAdded := AddMissingDefaultSpeedDials(entries)
        AssertEqual(results, "AddMissingDefaultSpeedDials voegt bij een tweede aanroep niets dubbel toe", secondAdded, 0)
        AssertEqual(results, "AddMissingDefaultSpeedDials laat de lijstlengte ongewijzigd bij herhaling", entries.Length, 2)

        entriesWithSameNumber := [CreateSpeedDialEntry("Andere naam", "1111", true)]
        addedWithSameNumber := AddMissingDefaultSpeedDials(entriesWithSameNumber)
        AssertEqual(
            results,
            "AddMissingDefaultSpeedDials herkent een bestaand nummer ook onder een andere naam",
            addedWithSameNumber,
            1
        )
    } finally {
        LocalConfig := originalConfig
    }
}

TestCreateSpeedDialEntryDefaults(results) {
    entry := CreateSpeedDialEntry("Testnaam", "0123456789")
    AssertEqual(results, "CreateSpeedDialEntry zet actief standaard op true", entry["actief"], true)

    inactive := CreateSpeedDialEntry("Testnaam", "0123456789", 0)
    AssertEqual(results, "CreateSpeedDialEntry zet actief op false bij een falsy waarde", inactive["actief"], false)
}
