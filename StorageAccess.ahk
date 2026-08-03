; =============================================================================
; DocBot opslagcontrole
; =============================================================================
; Controleert bij het opstarten of de gebruikersmap en ieder bestaand,
; door DocBot beheerd gegevensbestand daadwerkelijk schrijfbaar zijn.

ValidateUserStorageAccess(configFile) {
    SplitPath(configFile, , &storageDir)

    if storageDir = "" {
        throw Error(
            "De gebruikersmap kon niet uit het instellingenpad worden bepaald.`n`n"
            . configFile
        )
    }

    if !DirExist(storageDir) {
        throw Error(
            "De gebruikersmap bestaat niet.`n`n"
            . storageDir
        )
    }

    AssertUserStorageDirectoryWritable(storageDir)

    managedFiles := [
        configFile,
        storageDir "\hotstrings.json",
        storageDir "\package-settings.json",
        storageDir "\speeddial.json"
    ]

    for _, path in managedFiles {
        if FileExist(path)
            AssertUserStorageFileWritable(path)
    }
}

AssertUserStorageDirectoryWritable(directory) {
    probePath := directory
        . "\.docbot-write-test-"
        . A_NowUTC
        . "-"
        . A_TickCount
        . "-"
        . Random(100000, 999999)
        . ".tmp"
    probeFile := 0

    try {
        probeFile := FileOpen(probePath, "w", "UTF-8-RAW")
        if !IsObject(probeFile)
            throw Error("Het tijdelijke testbestand kon niet worden geopend.")

        probeFile.Write("DocBot schrijftest")
        probeFile.Close()
        probeFile := 0

        FileDelete(probePath)
    } catch as error {
        if IsObject(probeFile)
            try probeFile.Close()

        if FileExist(probePath)
            try FileDelete(probePath)

        throw Error(
            "DocBot kan niet schrijven in de gebruikersmap.`n`n"
            . directory
            . "`n`n"
            . error.Message
        )
    }
}

AssertUserStorageFileWritable(path) {
    try {
        attributes := FileGetAttrib(path)

        if InStr(attributes, "D") {
            throw Error(
                "DocBot verwachtte een bestand, maar vond een map.`n`n"
                . path
            )
        }

        if InStr(attributes, "R") {
            throw Error(
                "Dit DocBot-bestand is alleen-lezen.`n`n"
                . path
            )
        }

        file := FileOpen(path, "rw")
        if !IsObject(file) {
            throw Error(
                "Het bestand kon niet voor lezen en schrijven worden geopend.`n`n"
                . path
            )
        }

        file.Close()
    } catch as error {
        if IsSet(file) && IsObject(file)
            try file.Close()

        if InStr(error.Message, path)
            throw error

        throw Error(
            "DocBot kan dit bestand niet wijzigen.`n`n"
            . path
            . "`n`n"
            . error.Message
        )
    }
}
