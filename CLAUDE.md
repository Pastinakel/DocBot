HK v2 (niet v1 — syntax verschilt fors)

DocBot is een AutoHotkey v2-hulpmiddel voor medewerkers met twee hoofdfuncties:
tekstvervanging via hotstrings, en bellen via de interne IP-telefonie van het
ziekenhuis met automatische detectie van telefoonnummers op het klembord.

"Organisch gegroeid", was toe aan refactoring — DocBot.ahk is de nieuwe versie
met een compleet nieuwe interface (sidebar-navigatie, cards, tray-menu).

Bestanden
---------
- `DocBot.ahk` — huidig hoofdscript, hier werk je aan. Hotstrings + telefonie.
- `DocBot-LegacyV2.ahk` — vorige versie, alleen ter referentie, niet meer
  onderhouden.
- `JXON.ahk` — JSON-library (TheArkive, MIT), gebruikt voor hotstring-opslag.

Distributie
-----------
Het script wordt gecompileerd en uitsluitend als executable aan de
eindgebruiker aangeboden (niet als losse .ahk-broncode), zodat de
eindgebruiker het niet zelf kan aanpassen. Wijzigingen horen dus altijd in de
.ahk-bronbestanden hier in de repo; compileren/uitleveren gebeurt daarna
apart door de gebruiker.

Opslag op de gebruikerscomputer (niet in de repo)
--------------------------------------------------
- Hotstrings: `%MyDocuments%\DocBot\hotstrings.json`
- Instellingen: `%MyDocuments%\DocBot\settings.ini`
- Debug-log (telefonie-diagnostiek): `%LocalAppData%\DocBot\debug.log`

Telefonie
---------
Werkt uitsluitend binnen het ziekenhuisnetwerk (interne telefonieserver,
niet van buitenaf bereikbaar). Endpoints: `registratie-endpoint` (registratie),
`event-endpoint` (long-poll voor events), `bel-endpoint` (bellen). Alle
aanroepen zijn POST; configuratie staat in `IPTConfig`, live status in
`State["IPT"]` (beide bovenaan `DocBot.ahk`).

Zie `README.md` voor de volledige documentatie: installatie, functionaliteit
in detail, technische achtergrond van de IP-telefonie-API, diagnostiek en
changelog.

AHK v2: volgorde van globale variabelen
----------------------------------------
AHK v2 voert top-level statements in bestandsvolgorde uit; functiedefinities
zelf worden daarbij overgeslagen, maar een `global X := ...`-initialisatie
die pas ná de aanroep staat die `X` gebruikt, is op dat moment nog niet
uitgevoerd. Alle global-declaraties die nodig zijn vóór of tijdens het
opbouwen van de GUI (dus alles wat direct of indirect vanuit
`BuildMainGui()` gelezen wordt, zoals `RoundQueue`, `RoundedRadii`,
`ControlHomePos`, `GdipToken`) horen daarom bovenaan het bestand te staan,
in het bestaande globals-blok vóór het auto-execute-gedeelte — nooit
verderop bij een functionele sectie zoals "AFRONDING", ook al voelt die
sectie inhoudelijk logischer aan voor die specifieke variabele.

Branch-workflow: main vs. develop
---------------------------------
`main` is exact gelijk aan wat er als `.exe` bij de eindgebruiker draait.
Nieuwe werkinstructies worden uitgevoerd op branches die getakt zijn van
`develop`, niet van `main`. Begin elke sessie met `git fetch --prune`,
controleer via `git status`/`git branch -vv` of de huidige branch nog
bestaat op de remote, en maak de nieuwe werk-branch vanaf een actuele
`develop`:

```
git checkout develop
git pull origin develop
git checkout -b claude/<omschrijving>
```

Na afronding wordt er gemerged in `develop`, niet in `main`.

`main` wordt normaal gesproken uitsluitend bijgewerkt bij een release:
mergen vanuit `develop`, versie ophogen, changelog in het Over-scherm
bijwerken, annotated tag aanmaken en pushen (zie de releaseregel hieronder).

**Uitzondering:** alleen wanneer expliciet wordt aangegeven dat het om een
bugfix op `main` gaat (bijvoorbeeld een spoedfix voor iets dat al gedeployed
is), mag er rechtstreeks vanaf `main` getakt en teruggemergd worden — buiten
de normale `develop`-flow om. Ga hier nooit standaard van uit; zonder die
expliciete aanwijzing is `develop` altijd het startpunt. Vergeet bij zo'n
main-hotfix niet om de wijziging ook naar `develop` te mergen
(`git checkout develop && git merge main`), zodat `develop` niet achterloopt
op een fix die al in `main` zit.

Versiegeschiedenis en tags bij het ophogen van AppVersion
----------------------------------------------------------
Bij het ophogen van `AppVersion` in `DocBot.ahk` hoort, in dezelfde
commit-cyclus:
1. De versiegeschiedenis in het Over-scherm (`BuildAboutText()` in
   `BuildMainGui()`) bijwerken met een korte, globale samenvatting (1 tot
   max 3 regels) van wat er in die versie is veranderd.
2. Een annotated git tag aanmaken die overeenkomt met de nieuwe
   `AppVersion`-waarde, met een `v`-prefix, op de commit waarin die
   wijziging is doorgevoerd — bijv. `AppVersion := "2.0.0-beta.2"` →
   `git tag -a v2.0.0-beta.2 -m "2.0.0-beta.2"` op dat commit.
3. De tag meepushen: `git push origin --tags`.

Wijzigingen die nog niet onder een verhoogd versienummer zijn gebracht,
horen nog niet in deze changelog thuis en krijgen nog geen tag — werk-in-
uitvoering op de huidige branch hoort niet in de changelog én niet in de
tags totdat `AppVersion` daadwerkelijk is opgehoogd.

Let op: als het pushen van de tag mislukt (bijv. doordat de gebruikte
git-remote/proxy tag-refs blokkeert terwijl gewone branch-pushes wel
werken), moet dat expliciet gemeld worden in plaats van stilzwijgend
overgeslagen — de tag telt pas als klaar zodra die zichtbaar is op
`origin`.


## Lokale configuratie

Interne telefonieadressen, endpointnamen, standaard-snelkiesnummers en
standaard-hotstrings staan uitsluitend in `DocBot.local.ahk`. Dit bestand
wordt door Git genegeerd en mag nooit worden gecommit. Gebruik
`DocBot.local.example.ahk` als veilige structuurtemplate zonder echte
waarden. Ahk2Exe neemt de lokale include tijdens compilatie op.
