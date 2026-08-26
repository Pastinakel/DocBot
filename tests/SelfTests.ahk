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
; InitializeBundledPackages() in DocBot.ahk), de idempotentie van de
; eenmalige standaardwaarde-migraties voor persoonlijke hotstrings en
; snelkiesnummers (AddMissingDefaultHotstrings / AddMissingDefaultSpeedDials),
; de gebruikersprofielkeuze (GetUserDataProfile; docs/DECISIONS.md D-056) en
; de telefoonnummernormalisatie (NormalizePhoneNumber en de interne/externe
; varianten, NormalizeSmsPhoneNumber).
; Dit dekt bewust niet de bestands-I/O, GUI-vernieuwing of showMessage-paden
; van LoadHotstringsFromJson/LoadSpeedDialFromJson zelf, en ook niet de
; daadwerkelijke profiel-bootstrapkopie (InitializeUserStorage) — dat vereist
; Windows-functionele validatie (D-037).
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
    RunSelfTestCase(results, "TestGetUserDataProfile", TestGetUserDataProfile)
    RunSelfTestCase(results, "TestNormalizePhoneNumberInternal", TestNormalizePhoneNumberInternal)
    RunSelfTestCase(results, "TestNormalizePhoneNumberExternal", TestNormalizePhoneNumberExternal)
    RunSelfTestCase(results, "TestNormalizePhoneNumber", TestNormalizePhoneNumber)
    RunSelfTestCase(results, "TestNormalizeSmsPhoneNumber", TestNormalizeSmsPhoneNumber)

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
    try FileAppend(logText, logPath, "UTF-8-RAW")
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

; Dekt de testmatrix uit docs/TODO.md ("P2 — Change user-data profile
; selection to build mode") voor de acht stabiliteit x buildvorm-combinaties.
; Stable heeft voorrang; binnen niet-stabiel bepaalt uitsluitend isCompiled,
; nooit het prereleaselabel zelf, of het testprofiel of het devprofiel wordt
; gebruikt (docs/DECISIONS.md D-056).
TestGetUserDataProfile(results) {
    AssertEqual(results, "Stabiel, compiled -> main", GetUserDataProfile("2.3", true), "main")
    AssertEqual(results, "Stabiel, noncompiled -> main", GetUserDataProfile("2.3", false), "main")

    AssertEqual(results, "-dev, compiled -> test", GetUserDataProfile("2.3-dev.7", true), "test")
    AssertEqual(results, "-dev, noncompiled -> dev", GetUserDataProfile("2.3-dev.7", false), "dev")

    AssertEqual(results, "-rc, compiled -> test", GetUserDataProfile("2.3-rc.1", true), "test")
    AssertEqual(results, "-rc, noncompiled -> dev", GetUserDataProfile("2.3-rc.1", false), "dev")

    AssertEqual(
        results,
        "Feature/fixlabel, compiled -> test",
        GetUserDataProfile("2.3-profielselectie-build-vorm.1", true),
        "test"
    )
    AssertEqual(
        results,
        "Feature/fixlabel, noncompiled -> dev",
        GetUserDataProfile("2.3-profielselectie-build-vorm.1", false),
        "dev"
    )
}

; Uitsluitend het kale 4-cijferige interne nummer; DocBot.ahk:4112-4116.
TestNormalizePhoneNumberInternal(results) {
    AssertEqual(results, "NormalizePhoneNumberInternal accepteert een kaal 4-cijferig nummer", NormalizePhoneNumberInternal("1234"), "1234")
    AssertEqual(results, "NormalizePhoneNumberInternal negeert omringende spaties", NormalizePhoneNumberInternal(" 1234 "), "1234")
    AssertEqual(results, "NormalizePhoneNumberInternal wijst een 5-cijferig nummer af", NormalizePhoneNumberInternal("12345"), "")
    AssertEqual(results, "NormalizePhoneNumberInternal wijst een te kort nummer af", NormalizePhoneNumberInternal("123"), "")
    AssertEqual(results, "NormalizePhoneNumberInternal wijst een niet-numeriek nummer af", NormalizePhoneNumberInternal("12a4"), "")
}

; Uitsluitend externe (10-cijferige) NL-nummers, met of zonder landcode;
; DocBot.ahk:4097-4110.
TestNormalizePhoneNumberExternal(results) {
    AssertEqual(
        results,
        "NormalizePhoneNumberExternal accepteert een kaal nationaal NL-nummer",
        NormalizePhoneNumberExternal("0612345678"),
        "0612345678"
    )
    AssertEqual(
        results,
        "NormalizePhoneNumberExternal normaliseert +31 naar de nationale 0-vorm",
        NormalizePhoneNumberExternal("+31612345678"),
        "0612345678"
    )
    AssertEqual(
        results,
        "NormalizePhoneNumberExternal normaliseert 0031 naar de nationale 0-vorm",
        NormalizePhoneNumberExternal("0031612345678"),
        "0612345678"
    )
    AssertEqual(results, "NormalizePhoneNumberExternal wijst een te kort nummer af", NormalizePhoneNumberExternal("061234567"), "")
    AssertEqual(results, "NormalizePhoneNumberExternal wijst een 4-cijferig intern nummer af", NormalizePhoneNumberExternal("1234"), "")
}

; De combinatiefunctie die de klemborddetectie gebruikt: eerst het interne
; 4-cijferige nummer, anders de NL-specifieke externe vorm (+31/0031/0),
; met spaties/streepjes/haakjes genegeerd; DocBot.ahk:4079-4095.
TestNormalizePhoneNumber(results) {
    AssertEqual(results, "NormalizePhoneNumber herkent een kaal 4-cijferig intern nummer", NormalizePhoneNumber("1234"), "1234")
    AssertEqual(
        results,
        "NormalizePhoneNumber negeert spaties/streepjes bij een getypt nationaal nummer",
        NormalizePhoneNumber("06-12 34 56 78"),
        "0612345678"
    )
    AssertEqual(
        results,
        "NormalizePhoneNumber normaliseert een getypt +31-nummer met spaties naar de nationale vorm",
        NormalizePhoneNumber("+31 6 12 34 56 78"),
        "0612345678"
    )
    AssertEqual(
        results,
        "NormalizePhoneNumber normaliseert een kale 0031-vorm naar de nationale vorm",
        NormalizePhoneNumber("0031612345678"),
        "0612345678"
    )
    AssertEqual(results, "NormalizePhoneNumber wijst een te kort nummer af", NormalizePhoneNumber("061234567"), "")
    AssertEqual(results, "NormalizePhoneNumber wijst niet-numerieke invoer af", NormalizePhoneNumber("hallo"), "")
}

; Uitsluitend geldige NL-mobiele (06) nummers voor de SMS-actie, met of
; zonder landcode; DocBot.ahk:4909-4918.
TestNormalizeSmsPhoneNumber(results) {
    AssertEqual(
        results,
        "NormalizeSmsPhoneNumber accepteert een kaal 06-mobiel nummer",
        NormalizeSmsPhoneNumber("0612345678"),
        "0612345678"
    )
    AssertEqual(
        results,
        "NormalizeSmsPhoneNumber normaliseert +31 6... naar de 06-vorm",
        NormalizeSmsPhoneNumber("+31612345678"),
        "0612345678"
    )
    AssertEqual(
        results,
        "NormalizeSmsPhoneNumber normaliseert 0031 6... naar de 06-vorm",
        NormalizeSmsPhoneNumber("0031612345678"),
        "0612345678"
    )
    AssertEqual(results, "NormalizeSmsPhoneNumber wijst een niet-mobiel 05-nummer af", NormalizeSmsPhoneNumber("0512345678"), "")
    AssertEqual(results, "NormalizeSmsPhoneNumber wijst een te kort nummer af", NormalizeSmsPhoneNumber("061234567"), "")
    AssertEqual(results, "NormalizeSmsPhoneNumber wijst lege invoer af", NormalizeSmsPhoneNumber(""), "")
}
