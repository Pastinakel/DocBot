# DocBot — Gegevensbescherming en DPIA-screening

_Status: technisch concept met openstaande organisatorische invulpunten._

_Opgesteld: 2026-08-09._

_Onderzochte basis: branch `release/2.2-rc`, DocBot `2.2-rc.3`._

_Dit document is geen juridisch advies, verwerkingsregister, goedgekeurde DPIA
of vervanging van het privacy- en informatiebeveiligingsdossier van de
gebruikende organisatie._

## 1. Doel en afbakening

Dit document beschrijft de persoonsgegevensstromen die uit de repository en
de huidige ziekenhuisinzet van DocBot blijken. Het legt vast:

- welke gegevens DocBot technisch verwerkt;
- uit welke bron zij komen en naar welke bestemming zij gaan;
- wat lokaal wordt opgeslagen of tijdelijk in geheugen staat;
- welke technische autorisatie- en beveiligingsmaatregelen zichtbaar zijn;
- welke organisatorische rollen, grondslagen, ontvangers en bewaartermijnen
  nog moeten worden vastgesteld;
- waarom een formele DPIA-screening door de verwerkingsverantwoordelijke en
  diens functionaris gegevensbescherming nodig is.

De intended purpose en uitgesloten medische toepassingen staan in
`docs/INTENDED_PURPOSE.md`. De voorlopige MDR- en normenbeoordeling staat in
`docs/REGULATORY_ASSESSMENT.md`.

`OPENSTAAND` betekent dat het antwoord niet betrouwbaar uit de repository kan
worden afgeleid en door de verantwoordelijke organisatie moet worden
ingevuld. Een openstaand veld is geen bewijs dat geen maatregel of afspraak
bestaat.

## 2. Systemen en opslaglocaties

### 2.1 DocBot en Windows

DocBot draait als gecompileerde AutoHotkey v2-applicatie binnen het
Windows-account van de medewerker. De applicatie gebruikt:

- Windows Documents, mogelijk door OneDrive beheerd, voor gebruikersgegevens;
- LocalAppData voor diagnostiek en uitgepakte pakketcache;
- het Windows-klembord voor telefoonnummerdetectie;
- de actieve applicatie voor hotstringuitvoer;
- het tijdelijke Windows-pad voor ZIP-probleemrapporten.

### 2.2 Persistente gebruikersbestanden

Afhankelijk van het releasekanaal staan deze bestanden onder
`%MyDocuments%\DocBot`, `DocBot-test` of `DocBot-dev`:

| Bestand | Inhoud | Mogelijke persoonsgegevens |
| --- | --- | --- |
| `settings.ini` | Instellingen, installatie-ID en gebruikstellers | Installatie-ID en gebruiksstatus van een medewerker/installatie |
| `hotstrings.json` | Persoonlijke afkortingen en vervangteksten | Mogelijke persoonsgegevens van de medewerker, zoals naam, telefoonnummer of e-mailadres; klinische tekst is generiek en niet patiëntgebonden |
| `package-settings.json` | Pakketstatussen en conflictkeuzes | Normaal geen directe persoonsgegevens |
| `speeddial.json` | Namen, nummers en actiefstatus | Persoons-, medewerker- of organisatienummers |

Schrijfroutines gebruiken waar geïmplementeerd tijdelijke bestanden,
validatie en `.bak`-back-ups. DocBot richt geen eigen versleuteling of
expliciete bestands-ACL's in; toegang berust op Windows, het gebruikersprofiel,
OneDrive en organisatorisch werkplekbeheer.

### 2.3 LocalAppData en tijdelijke bestanden

| Locatie | Inhoud | Technische begrenzing/verwijdering |
| --- | --- | --- |
| `%LocalAppData%\DocBot\debug.log` | Centraal geredigeerde diagnostiek | Rotatie boven circa 2 MB naar één `.oud`-bestand |
| `%LocalAppData%\DocBot\<tijdelijk uitgebreid log>` | Ongeredigeerde diagnostiek tijdens toegestane sessie | Verwijderd bij afsluiten, nieuwe sessie en na succesvolle rapportvoorbereiding |
| `%TEMP%\DocBot_diagnose_<tijdstip>.zip` | Beschrijving, standaardlog en optioneel uitgebreid log | Blijft na voorbereiding beschikbaar voor e-mail/handmatige verzending |
| `%LocalAppData%\DocBot[-dev]\packages` | Uitgepakte ingebouwde pakketten | Pakketinhoud, normaal geen gebruikers- of patiëntgegevens |

## 3. Gegevensstromen

### 3.1 Klembord en telefoonnummerdetectie

**Doel:** een gekopieerd telefoonnummer herkennen en de gekozen bel- of
SMS-actie uitvoeren.

**Feitelijke stroom:**

```text
Windows-klembord
  -> DocBot leest nieuwe klembordinhoud lokaal
  -> technische validatie/normalisatie
  -> geen geldig nummer: geen verdere telefoonactie
  -> geldig nummer: tijdelijk in State["IPT"]["ClipBoardNumber"]
       -> negeren / bevestigingsvenster / direct bellen / keuze bellen-SMS
```

DocBot controleert eerst het wijzigingsnummer van het Windows-klembord en
leest bij een wijziging de inhoud om te bepalen of deze een ondersteund
telefoonnummer is. Daardoor wordt technisch kortstondig ook klembordtekst
gelezen die uiteindelijk geen telefoonnummer blijkt te zijn. DocBot slaat die
niet-herkende inhoud niet bewust op of extern door.

**Gegevens:** Nederlandse externe telefoonnummers, interne viercijferige
nummers en kortstondig de onderzochte klembordinhoud.

**Betrokkenen:** patiënten, medewerkers, contactpersonen en andere personen
van wie een nummer wordt gekopieerd.

**Lokale bewaring:** een herkend nummer blijft tijdens het proces in de
IPT-statusmap in geheugen. Er is geen eigen persistente telefoonnummerdatabase
voor klembordnummers.

**Ontvangers:** geen bij negeren; interne telefonieserver bij bellen; de
geconfigureerde SMS-webapplicatie bij SMS-assistentie.

**OPENSTAAND:** organisatorisch doel, grondslag, maximale geheugenduur,
informatie aan betrokkenen en dekking door het verwerkingsregister.

### 3.2 Interne telefonie

**Doel:** telefoon koppelen, telefoniestatus ontvangen en een gekozen nummer
laten bellen.

DocBot verstuurt POST-aanvragen naar lokaal geconfigureerde registratie-,
event- en bel-endpoints. Een belnummer staat als queryparameter in de URL van
de POST-aanvraag. Serverresponsen kunnen koppel- of toestelgegevens en
statusmeldingen bevatten. De standaardlog schermt URL's, telefoon- en interne
nummers en responsinhoud af; tijdens expliciet ingeschakelde uitgebreide
logging kunnen oorspronkelijke waarden in het tijdelijke log komen.

| Onderdeel | Vastgesteld uit repository | OPENSTAAND |
| --- | --- | --- |
| Ontvanger | Lokaal geconfigureerde interne telefonieserver | Juridische entiteit, beheerder en eventuele verwerker |
| Transport | Protocol volgt `IPTConfig["URL"]`; voorbeeldconfiguratie gebruikt `https://` | Code dwingt HTTPS nog niet af; productieprotocol, TLS-versie, certificaatcontrole en netwerksegmentatie bevestigen |
| Authenticatie | Geen applicatie-eigen gebruikersauthenticatie zichtbaar; technisch `sid`-veld wordt gebruikt | Serverauthenticatie, autorisatiemodel en misbruikbeveiliging |
| Serverlogging | Niet zichtbaar in repository | Inhoud, toegang, bewaartermijn en verwijdering |
| Doorgifte buiten EER | Niet zichtbaar | Bevestigen dat geen doorgifte plaatsvindt, of grondslag/waarborgen vastleggen |

De voorbeeldconfiguratie stuurt nu naar HTTPS. Een openstaande projecttaak
verlangt daarnaast technische HTTPS-validatie voor telefonie en blokkering van
HTTP. Totdat dit functioneel is geïmplementeerd en in productie is bevestigd,
blijft transportbeveiliging een expliciet risico.

### 3.3 SMS-assistentie via Edge

**Doel:** een Nederlands mobiel nummer in een door de gebruiker gekozen
SMS-webpagina invullen.

DocBot activeert of opent een lokaal geconfigureerde Edge-pagina, zoekt het
telefoonveld via UI Automation en vult het nummer in. JavaScript is een
fallback. DocBot maakt en verzendt zelf geen SMS-bericht.

**Gegevens:** mobiel telefoonnummer, technische paginatitel, URL en veld-ID.

**Ontvanger:** de geconfigureerde SMS-webapplicatie en de organisatie of
leverancier die deze beheert.

**Transport:** de voorbeeldconfiguratie gebruikt een HTTPS-URL. De code
controleert alleen of `SmsCallAction.Url` is ingevuld en dwingt HTTPS nog niet
af. Een lokaal geconfigureerde HTTP-pagina kan daardoor worden geopend en door
DocBot met een telefoonnummer worden gevuld.

**Bewaring door DocBot:** geen afzonderlijke persistente SMS-opslag. Bij
uitgebreide logging kunnen nummer- of technische foutdetails tijdelijk worden
vastgelegd.

**OPENSTAAND:** naam en rol leverancier, verwerkersovereenkomst, browser- en
serverlogging, cookies/lokale opslag, autorisaties, bewaartermijn, TLS-eisen,
eventuele doorgifte buiten de EER en informatie aan betrokkenen.

### 3.4 Hotstrings en pakketinhoud

**Doel:** door de gebruiker gekozen tekst in de actieve applicatie invoegen.

Persoonlijke hotstrings worden in lokale JSON opgeslagen. Ingebouwde pakketten
komen uit versiebeheer en worden lokaal uitgepakt. Bij uitvoering stuurt
DocBot de vervangtekst naar de actieve applicatie. Hotstringuitvoer gebruikt
niet het Windows-klembord.

**Gegevens:** afkorting, vervangtekst, pakketkeuze en optioneel datum/tijd.
Vervangteksten zijn bedoeld als generieke, herbruikbare formuleringen. Zij
kunnen persoonsgegevens van de medewerker bevatten, zoals een naam,
telefoonnummer, e-mailadres of ondertekening. Klinische formuleringen zoals
`geen afwijkingen` of `Op {{datum}} zag ik uw patiënt` beschrijven geen
geïdentificeerde of identificeerbare patiënt en zijn daardoor op zichzelf geen
patiënt- of gezondheidsgegevens.

Patiëntidentificerende of patiëntspecifieke informatie is niet beoogd als
inhoud van `hotstrings.json` en hoort daar niet in te worden opgeslagen. Het
vrije `Replacement`-veld bevat momenteel geen technische controle die dit
afdwingt; naleving berust daarom op gebruikersinstructie en organisatorisch
beleid.

**Ontvanger:** de actieve applicatie en het actieve veld; in de huidige
ziekenhuisomgeving kan dit een EPD zijn.

**Bewaring:** persoonlijke hotstrings blijven bestaan tot de gebruiker ze
wijzigt of verwijdert, het profiel wordt verwijderd of een organisatorische
beheeractie plaatsvindt. `.bak`-bestanden kunnen een eerdere versie bevatten.

**Autorisatie:** het Windows-account kan de eigen bestanden benaderen. DocBot
controleert niet of de juiste patiënt, applicatie of het juiste veld actief is.

**OPENSTAAND:** organisatorische bewaartermijn, verwijdering bij
uitdiensttreding/functiewijziging, toegangsbeheer OneDrive/back-ups,
inhoudseigenaarschap van medische pakketten, gebruikersinstructie die
patiëntspecifieke inhoud uitsluit en toepasselijke grondslag voor eventuele
medewerkergegevens.

### 3.5 Snelkiesnummers en instellingen

**Doel:** persoonlijke of organisatorische snelkiesacties en functionele
voorkeuren bewaren.

Snelkiesnamen en nummers staan in `speeddial.json`. Instellingen,
telemetrie-identificatie en gebruikstellers staan in `settings.ini`.

**Ontvangers:** primair de lokale gebruiker; OneDrive en centraal
werkplekbeheer kunnen technisch betrokken zijn bij opslag of back-up.

**OPENSTAAND:** toegestane inhoud, zakelijke versus persoonlijke nummers,
bewaartermijn, back-uptermijn, toegang door beheerders en verwijdering van het
gebruikersprofiel.

### 3.6 Standaarddiagnostiek

**Doel:** technische storingen onderzoeken zonder standaard gevoelige inhoud
te bewaren.

De standaardlog:

- vervangt gebruikers- en computernaam;
- schermt lokale en netwerkpaden af;
- schermt URL's en herkenbare telefoon-/interne nummers af;
- neemt bepaalde gestructureerde inhoud en serverresponses niet op;
- kapt individuele geschoonde teksten boven 2.000 tekens af;
- roteert `debug.log` boven circa 2 MB naar `debug.log.oud`.

De applicatie verwijdert historische logs met een ouder, mogelijk
ongeredegeerd formaat bij initialisatie.

**Ontvangers:** lokale gebruiker; ontwikkelaarsdebugvenster voor het in de code
toegestane Windows-account; bij probleemrapportage de gekozen supportontvanger.

**OPENSTAAND:** maximale tijdsduur naast bestandsgrootte, autorisatie van het
ontwikkelaarsaccount, endpointbeveiliging van support en verwijdering bij
uitdiensttreding.

### 3.7 Uitgebreide logging en probleemrapportage

**Doel:** een door de gebruiker gereproduceerd technisch probleem onderzoeken.

Uitgebreide logging vereist een expliciet aangevinkt toestemmingsvak. Deze
toestemming is een technische gebruikershandeling en is niet zonder nadere
beoordeling de AVG-grondslag voor de verwerking.

Tijdens de sessie kunnen onder meer volledige telefoonnummers, URL's,
serverresponses, gebruikte hotstringtriggers en vervangteksten en SMS/UIA-
details worden vastgelegd. De telemetriewebhook blijft geredigeerd.

Bij afronding maakt DocBot in `%TEMP%` een ZIP met:

- `probleemrapport.txt` met versie, tijd, gebruikersbeschrijving en indicatie
  of uitgebreide logging is gebruikt;
- de standaardlog wanneer beschikbaar;
- het uitgebreide log wanneer gekozen en beschikbaar.

`settings.ini`, `hotstrings.json`, pakketconfiguratie en lokale
configuratiebestanden worden niet toegevoegd. De tijdelijke uitgepakte map en
het uitgebreide log worden verwijderd volgens de beschreven sessielogica. De
ZIP blijft beschikbaar en wordt aan een Classic-Outlook-concept gekoppeld of
in Verkenner geselecteerd voor handmatige toevoeging. De gebruiker verzendt
het e-mailbericht zelf.

| Onderwerp | Vastgesteld | OPENSTAAND |
| --- | --- | --- |
| Supportontvanger | Lokaal/configuratief bepaald | Naam, rol, mailbox en vervanging bij afwezigheid |
| ZIP op werkplek | Blijft in `%TEMP%` staan | Automatische of organisatorische verwijdertermijn |
| E-mail | Outlook-concept; verzending door gebruiker | Mailtransport, mailboxretentie, doorsturen en archivering |
| Toegang | Gebruiker en ontvangers van het rapport | Geautoriseerde supportgroep, periodieke toegangscontrole |
| Incidentproces | Niet volledig in repository | Classificatie, datalekprocedure en escalatie naar FG/CISO |

### 3.8 Optionele telemetrie

**Doel volgens README:** centraal inzicht in actieve installaties en
telefonie-/hotstringstatus.

Telemetrie is lokaal configureerbaar en verzendt via POST naar een verplicht
met `https://` beginnende Power Automate/Teams-webhook. De eerste heartbeat
volgt tien seconden na de start en daarna standaard iedere vijftien minuten.

De payload bevat:

- willekeurig lokaal installatie-ID;
- Windows-gebruikersnaam;
- applicatienaam en -versie;
- starttijd en laatst-gezien-tijd;
- telefoon-gekoppeld- en hotstrings-ingeschakeld-status;
- cumulatief aantal gestarte belacties;
- cumulatief aantal lange of meerregelige hotstringacties.

De payload bevat volgens code en README geen computernaam, gebelde nummers,
hotstringafkortingen, vervangteksten, pakketinhoud of klembordinhoud.

**Ontvangers:** lokaal geconfigureerde Power Automate/Teams-omgeving en de
personen met toegang tot de uiteindelijke bestemming.

**Lokale bewaring:** installatie-ID en cumulatieve tellers in `settings.ini`.

**OPENSTAAND:** formeel doel en noodzakelijkheid, AVG-grondslag voor
medewerkergegevens, informatie aan medewerkers, kanaal-/flow-eigenaarschap,
toegangsleden, Microsoft-contractketen, regio/doorgifte, bewaartermijn,
verwijdering en bezwaar-/inzagerechten.

## 4. Rollen en verantwoordelijkheden

Onderstaande tabel is een invulvoorstel. Rollen mogen pas als vastgesteld
worden beschouwd nadat de verantwoordelijke organisatie dit heeft bevestigd.

| Partij/rol | Voorlopige duiding | Status |
| --- | --- | --- |
| Gebruiksorganisatie/ziekenhuis | Waarschijnlijk verwerkingsverantwoordelijke voor patiënt- en medewerkersgegevens in de eigen werkprocessen | OPENSTAAND — formeel bevestigen |
| Medewerker | Geautoriseerde gebruiker onder verantwoordelijkheid van de organisatie | OPENSTAAND — gebruikersgroepen en mandaat vastleggen |
| Projecteigenaar/ontwikkelaar DocBot | Softwaremaker; alleen verwerker voor zover daadwerkelijk namens de organisatie persoonsgegevens worden verwerkt of ontvangen | OPENSTAAND — feitelijke support- en contractrol vaststellen |
| Beheerder telefonieserver | Interne beheerfunctie, verwerker of andere rol afhankelijk van organisatie en contract | OPENSTAAND |
| Aanbieder SMS-webapplicatie | Verwerker, subverwerker of zelfstandig verantwoordelijke afhankelijk van dienst en contract | OPENSTAAND |
| Microsoft/Power Automate/Teams/Outlook/OneDrive | Leverancier/verwerker binnen de Microsoft-contractketen | OPENSTAAND — contract, tenant, regio en subprocessors vastleggen |
| Ontvanger probleemrapport | Geautoriseerde interne of externe supportrol | OPENSTAAND — naam, mailbox, doel en toegang vastleggen |
| Functionaris gegevensbescherming | Adviseur/toezichthouder bij DPIA en AVG-beoordeling | OPENSTAAND — betrokkenheid en advies registreren |
| CISO/informatiebeveiliging | Beoordeling beveiligingsrisico's en maatregelen | OPENSTAAND — eigenaar aanwijzen |
| Klinisch/functioneel eigenaar | Eigenaarschap zorgproces en medische pakketinhoud | OPENSTAAND — eigenaar aanwijzen |

## 5. Doeleinden en grondslagen

De repository kan technische doeleinden beschrijven, maar kan niet bepalen
welke grondslag de gebruiksorganisatie rechtsgeldig toepast. Per doel moet
zowel een grondslag uit artikel 6 AVG als, bij gezondheidsgegevens, een
toepasselijke uitzondering uit artikel 9 AVG worden vastgelegd.

| Verwerkingsdoel | Mogelijk relevante beoordeling | Vast te stellen door |
| --- | --- | --- |
| Patiëntcommunicatie via bellen/SMS | Noodzaak voor zorgverlening of bedrijfsvoering; bij gezondheidsinformatie ook artikel 9 beoordelen | Privacyjurist/FG en proceseigenaar |
| Zorgdocumentatie via hotstrings | Noodzaak en proportionaliteit binnen dossier-/zorgproces; artikel 9 beoordelen | Privacyjurist/FG en klinisch eigenaar |
| Medewerkerinstellingen en snelkiezen | Noodzaak voor uitvoering werkproces | Privacyjurist/FG en werkgever |
| Standaarddiagnostiek | Noodzaak voor beveiliging, continuïteit en support; minimale gegevens aantonen | Privacyjurist/FG, CISO en supporteigenaar |
| Uitgebreide logging/probleemrapport | Noodzaak, subsidiariteit en waarborgen; vinkje niet automatisch als AVG-toestemming behandelen | Privacyjurist/FG en supporteigenaar |
| Telemetrie | Afzonderlijk doel, noodzakelijkheid, proportionaliteit en werknemerspositie beoordelen | Privacyjurist/FG, werkgever en producteigenaar |

**OPENSTAAND:** vul per doel de definitieve artikelen, nationale wettelijke
basis, noodzakelijkheid, gegevensminimalisatie en informatieplicht in. Neem de
uitkomst ook op in het verwerkingsregister van de organisatie.

## 6. Ontvangers en doorgiften

Voor iedere ontvanger moeten minimaal worden vastgelegd:

- naam en juridische entiteit;
- rol onder de AVG;
- doel en ontvangen gegevenscategorieën;
- contract of verwerkersovereenkomst;
- toegangsrollen en periodieke controle;
- opslagregio en eventuele doorgifte buiten de EER;
- toepasselijk doorgiftemechanisme en aanvullende waarborgen;
- bewaartermijn en verwijderprocedure;
- incident- en subverwerkersafspraken.

**OPENSTAAND ontvangersregister:** telefonieserverbeheer, SMS-aanbieder,
Microsoft-tenant en -diensten, supportmailbox/ticketsysteem, OneDrive-beheer en
eventuele back-up- of securitydienstverleners.

## 7. Bewaartermijnen

| Gegevens/verwerking | Technisch gedrag | Organisatorische termijn |
| --- | --- | --- |
| Niet-herkende klembordinhoud | Alleen lokaal onderzocht; niet bewust persistent opgeslagen | OPENSTAAND — bevestig dat geen andere werkpleklogging bestaat |
| Herkend klembordnummer | Tijdelijk in geheugen/status | OPENSTAAND — maximale procesduur vastleggen |
| Telefonieservergegevens | Buiten repository | OPENSTAAND |
| SMS-webappgegevens | Buiten repository | OPENSTAAND |
| Persoonlijke hotstrings | Tot wijziging/verwijdering/profielbeheer; `.bak` kan vorige versie bevatten | OPENSTAAND |
| Snelkiesnummers en instellingen | Tot wijziging/verwijdering/profielbeheer | OPENSTAAND |
| Standaardlog | Actief plus één geroteerd bestand; rotatie bij circa 2 MB | OPENSTAAND — maximale tijdsduur toevoegen |
| Uitgebreid log | Tijdelijk gedurende rapportsessie; volgens sessielogica verwijderd | Technische regel bevestigen in beheer-/testbewijs |
| Probleemrapport-ZIP | Blijft in `%TEMP%` na voorbereiding | OPENSTAAND — automatische of handmatige verwijdertermijn |
| Supportmail/ticket | Buiten repository | OPENSTAAND |
| Telemetrie lokaal | Installatie-ID en tellers in `settings.ini` | OPENSTAAND |
| Telemetrie extern | Power Automate/Teams-omgeving | OPENSTAAND |
| OneDrive/back-ups | Buiten repository | OPENSTAAND |

Termijnen moeten controleerbaar zijn en ook back-ups, mailboxen, exports en
uitdiensttreding omvatten. Alleen `zolang als nodig` is geen uitvoerbare
verwijderregel.

## 8. Autorisaties

### 8.1 Zichtbare technische maatregelen

- DocBot draait onder het Windows-account van de gebruiker.
- Het ontwikkelaarsdebugvenster is in de huidige code aan een specifiek
  Windows-account gekoppeld.
- Uitgebreide logging start alleen na een expliciet aangevinkt vak.
- De gebruiker kiest en verzendt het probleemrapport zelf.
- SMS-verzending blijft bij de gebruiker.
- Lokale configuratie met endpoints en secrets staat buiten Git.

### 8.2 Openstaande autorisatiematrix

Leg voor iedere rol lezen, wijzigen, uitvoeren, exporteren, verwijderen en
beheren vast voor:

- persoonlijke hotstrings, snelkiesnummers en instellingen;
- medische pakketinhoud en pakketvrijgave;
- standaard- en uitgebreide logs;
- probleemrapport-ZIP's, supportmailbox en tickets;
- telemetriewebhook, Power Automate-flow en Teams-kanaal;
- telefonie- en SMS-serverlogs;
- lokale configuratie en build-/distributieomgeving;
- OneDrive, back-ups en gebruikersprofielen.

**OPENSTAAND:** eigenaar per autorisatiegroep, aanvraag-/goedkeuringsproces,
periodieke review, logging van beheertoegang en intrekking bij rolwijziging of
uitdiensttreding.

## 9. Transport- en opslagbeveiliging

| Stroom | Huidige technische maatregel | Openstaand risico/actie |
| --- | --- | --- |
| Telefonie | Interne netwerkdienst; POST; voorbeeldconfiguratie gebruikt HTTPS | HTTPS in configuratie afdwingen, HTTP blokkeren, TLS/certificaat/authenticatie bevestigen |
| SMS | Voorbeeld-URL is HTTPS; Edge/browsercontext | HTTPS in iedere SMS-configuratie afdwingen, HTTP blokkeren, leverancier en browserbeveiliging vastleggen |
| Telemetrie | Code vereist een `https://`-webhook | Tenant, TLS-inspectie, ontvangers en retentie vastleggen |
| Probleemrapport per e-mail | Classic Outlook-concept of handmatige fallback | Mailtransport, classificatie, encryptie en externe ontvangers vastleggen |
| Documents/OneDrive | Windows-profiel en beheerde opslag | ACL's, tenant, synchronisatie, back-up en versleuteling bevestigen |
| LocalAppData/%TEMP% | Windows-profiel | Schijfversleuteling, endpointbeheer, tijdelijke ZIP-verwijdering bevestigen |

Aanvullend moeten secure development, kwetsbaarhedenbeheer, incidentrespons,
sleutel-/secretbeheer en logging van beheerhandelingen worden gekoppeld aan
het NEN 7510-beheersysteem van de organisatie.

## 10. DPIA-screening

### 10.1 Juridisch criterium

Artikel 35 AVG verlangt een DPIA vóór verwerking wanneer aard, omvang,
context en doelen waarschijnlijk een hoog risico opleveren. Grootschalige
verwerking van bijzondere persoonsgegevens is een expliciet genoemd geval. De
functionaris gegevensbescherming moet bij de beoordeling worden geraadpleegd.

Officiële bronnen:

- [AVG, artikel 35](https://eur-lex.europa.eu/legal-content/NL/TXT/?uri=CELEX%3A32016R0679);
- [EDPB — Data Protection Impact Assessment](https://www.edpb.europa.eu/topics/accountability-and-compliance-tools/data-protection-impact-assessment_en);
- [Autoriteit Persoonsgegevens — grootschalige gegevensverwerking in de zorg](https://www.autoriteitpersoonsgegevens.nl/actueel/ap-geeft-uitleg-over-grootschalige-gegevensverwerking-in-de-zorg).

### 10.2 Voorlopige criteria voor DocBot

| Criterium | Voorlopige beoordeling | Onderbouwing/open punt |
| --- | --- | --- |
| Bijzondere/zeer persoonlijke gegevens | Ja in huidige ziekenhuisinzet | Telefoonnummers en probleemrapporten/uitgebreide logs kunnen patiëntgebonden informatie bevatten; generieke klinische hotstringtekst is op zichzelf geen gezondheidsgegeven |
| Kwetsbare betrokkenen | Ja mogelijk | Patiënten; concrete patiëntgroepen OPENSTAAND |
| Grootschaligheid | Waarschijnlijk via ziekenhuiscontext | Aantal gebruikers, patiënten, locaties en frequentie OPENSTAAND |
| Systematische monitoring | Mogelijk | DocBot bewaakt klembordwijzigingen; bepaal of dit organisatorisch als monitoring van medewerkers/betrokkenen geldt |
| Geautomatiseerde actie | Ja, technisch | Direct bellen en automatische hotstringvervanging; geen medische besluitvorming |
| Koppelen/combineren gegevenssets | Beperkt zichtbaar | Geen eigen patiëntdatabase; externe systemen en logs OPENSTAAND |
| Nieuwe technologie/oplossing | Niet zonder meer | AutoHotkey/UIA is technisch ondersteunend; organisatorische beoordeling OPENSTAAND |
| Belemmering rechten/dienst | Niet aangetroffen als doel | Misrouting of foutieve vastlegging kan wel gevolgen hebben |

### 10.3 Voorlopige conclusie

Er moet minimaal een gedocumenteerde DPIA-screening plaatsvinden. Gezien de
ziekenhuiscontext, mogelijke gezondheidsinformatie, kwetsbare betrokkenen,
grootschalige zorgverwerking en systematische klembordbewaking is het
voorzichtige uitgangspunt dat een DPIA nodig kan zijn.

De verwerkingsverantwoordelijke en FG moeten één van deze uitkomsten
vastleggen:

1. DocBot valt volledig binnen een bestaande, actuele DPIA; vermeld titel,
   eigenaar, versie, datum en de expliciet gedekte DocBot-gegevensstromen.
2. Een bestaande DPIA vereist een DocBot-aanvulling; leg scope en deadline
   vast.
3. DocBot vereist een afzonderlijke DPIA; wijs eigenaar, methode en deadline
   toe.
4. Een DPIA is niet nodig; documenteer de criteria, motivering en het advies
   van de FG.

| Besluitveld | Invulling |
| --- | --- |
| Verwerkingsverantwoordelijke | OPENSTAAND |
| FG geraadpleegd | OPENSTAAND |
| Bestaande DPIA onderzocht | OPENSTAAND |
| Titel/versie bestaande DPIA | OPENSTAAND |
| Definitieve uitkomst | OPENSTAAND |
| Motivering | OPENSTAAND |
| Restrisico en maatregelen | OPENSTAAND |
| Besluitdatum | OPENSTAAND |
| Eigenaar en herbeoordelingsdatum | OPENSTAAND |

Als een DPIA ondanks maatregelen een hoog restrisico laat bestaan, moet de
organisatie beoordelen of voorafgaande raadpleging van de Autoriteit
Persoonsgegevens nodig is.

## 11. Actielijst en gereedcriteria

| Actie | Eigenaar | Deadline | Status |
| --- | --- | --- | --- |
| Verwerkingsverantwoordelijke en overige AVG-rollen bevestigen | OPENSTAAND | OPENSTAAND | Open |
| Doel en grondslag per verwerking vaststellen | OPENSTAAND | OPENSTAAND | Open |
| Ontvangers- en verwerkersregister invullen | OPENSTAAND | OPENSTAAND | Open |
| Bewaar- en verwijdertermijnen goedkeuren | OPENSTAAND | OPENSTAAND | Open |
| Autorisatiematrix opstellen en controleren | OPENSTAAND | OPENSTAAND | Open |
| Productietransport telefonie en SMS beoordelen en HTTPS afdwingen | OPENSTAAND | OPENSTAAND | Open |
| SMS-, Microsoft-, mail- en OneDrive-contractketen vastleggen | OPENSTAAND | OPENSTAAND | Open |
| DPIA-dekking of afzonderlijke DPIA met FG vaststellen | OPENSTAAND | OPENSTAAND | Open |
| Uitkomst koppelen aan verwerkingsregister en NEN 7510-risicoanalyse | OPENSTAAND | OPENSTAAND | Open |
| Medewerkers-/betrokkeneninformatie controleren | OPENSTAAND | OPENSTAAND | Open |

Deze vervolgactie is gereed wanneer alle `OPENSTAAND`-velden die voor de
productie-inzet relevant zijn ingevuld zijn of naar een formeel beheerd
organisatiedocument verwijzen, de FG de DPIA-screening heeft beoordeeld en
ieder restrisico een geaccepteerde maatregel, eigenaar en termijn heeft.

## 12. Wijzigingsbeheer

Herbeoordeel dit document bij wijzigingen aan:

- de intended purpose;
- gegevenscategorieën of betrokkenen;
- telemetrie- of loggingpayloads;
- ontvangers, leveranciers, endpoints of opslaglocaties;
- bewaartermijnen, autorisaties of transportbeveiliging;
- autonome acties of klinische pakketinhoud;
- de ziekenhuisbrede DPIA, het verwerkingsregister of relevante wetgeving.

Leg bij iedere herbeoordeling datum, versie, wijziging, beoordelaars, uitkomst
en eventuele nieuwe maatregelen vast.
