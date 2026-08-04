from pathlib import Path

path = Path("DocBot.ahk")
text = path.read_text(encoding="utf-8")

old_directory = '''    } catch as error {
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
}'''
new_directory = '''    } catch as caughtError {
        if IsObject(probeFile)
            try probeFile.Close()
        if FileExist(probePath)
            try FileDelete(probePath)

        throw Error(
            "DocBot kan niet schrijven in de gebruikersmap.`n`n"
            . directory
            . "`n`n"
            . caughtError.Message
        )
    }
}'''

old_file = '''    } catch as error {
        if IsObject(file)
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
}'''
new_file = '''    } catch as caughtError {
        if IsObject(file)
            try file.Close()

        if InStr(caughtError.Message, path)
            throw caughtError

        throw Error(
            "DocBot kan dit bestand niet wijzigen.`n`n"
            . path
            . "`n`n"
            . caughtError.Message
        )
    }
}'''

if text.count(old_directory) != 1:
    raise RuntimeError("Directory catch block not found exactly once")
if text.count(old_file) != 1:
    raise RuntimeError("File catch block not found exactly once")

text = text.replace(old_directory, new_directory, 1)
text = text.replace(old_file, new_file, 1)
path.write_text(text, encoding="utf-8", newline="\n")
