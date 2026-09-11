# Survivor Leveling & Advancement [B42]

Optjen point ved at udvikle dine færdigheder, og brug dem på de færdigheder, du vælger. SLA tilføjer overleverniveau og avancementspoint til det normale færdighedspanel og bevarer den naturlige udvikling. Skal noget af fremskridtet overleve din næste dårlige beslutning? Valgfri niveauarv lader din næste figur beholde en procentdel af dit overleverniveau med nye point at bruge.

Understøtter singleplayer, multiplayer, delt skærm og controller. Ingen påkrævede afhængigheder.

## Sådan fungerer avancement

XP fra understøttede færdigheder øger også dit overleverniveau. Hvert overleverniveau giver ét avancementspoint, eller AP. Brug AP med **+**-knapperne ved færdighederne. Som standard kan tre avancementspladser være optaget ad gangen. Øv en avanceret færdighed for at indhente de oversprungne XP og frigøre dens pladser. Disse XP tæller også mod færdighedens næste niveau.

Det sidste avancement til en færdigheds effektive maksimum, normalt fra niveau 9 til 10, regnes som mestring. Det koster 2 AP og kræver 2 ledige avancementspladser, hvorefter alle aktive pladser på færdigheden frigøres. Er grænsen for Fælles eller Pr. færdighed sat til 1, kræver mestring kun 1 ledig plads, men koster stadig 2 AP. Fri kræver ingen pladser og koster fortsat 2 AP. En færdighed på sit effektive maksimum giver ikke flere overlever-XP.

## Behold noget af fremskridtet efter døden

Aktivér arv af overleverniveau, og vælg, hvor meget din næste figur i samme verden får. Dør du for eksempel på overleverniveau 20 med 50% arv, får din næste figur overleverniveau 10 og 10 AP. De gamle færdighedsniveauer kopieres ikke, så du vælger selv, hvor de arvede point bruges. Arv er valgfri og slået fra som standard.

## Indstillinger

- **Fælles:** Alle færdigheder deler en justerbar pulje af avancementspladser. Standardgrænsen er 3 aktive pladser i alt.
- **Pr. færdighed:** Hver færdighed har sin egen justerbare grænse med en standardværdi til kompatible modfærdigheder og valgfrie særindstillinger til grundspillets færdigheder.
- **Fri:** Fjerner pladsgrænser og begrænsninger ved indhentning af XP.
- Justér hastigheden for overlever-XP uden at ændre færdigheds-XP. Vælg, om kondition, styrke, de enkelte grundfærdigheder og kompatible modfærdigheder bidrager.
- Aktivér avancementsmarkører med højere kontrast eller spiller 1's overlever-XP i procent på digitaluret under modindstillinger.
- Understøtter alle standardsprog i Project Zomboids sprogindstillinger. Alle oversættelser er udelukkende lavet med AI. Meld gerne forkert eller uklart sprog.

**Bemærk:** Tilstandsskift nulstiller ikke registreret fremskridt. Naturlige færdigheds-XP optjent i Fri tæller stadig mod bevaret blå indhentning. Skift tilbage til Fælles eller Pr. færdighed gendanner kun det, der mangler.

## Tilføj eller fjern SLA

SLA kan tilføjes til og fjernes fra eksisterende gemte spil. Færdigheder bevares, og tidligere fremskridt giver ikke overleverniveauer med tilbagevirkende kraft. Deaktivering skjuler SLA's brugerflade, men bevarer færdighedsniveauer købt med AP. Genaktivering gendanner SLA's tilstand og medregner understøttet fremskridt fra tiden uden SLA. Som ved enhver ændring af modlisten anbefaler jeg kraftigt at sikkerhedskopiere igangværende verdener, du vil bevare.

## Dedikerede servere og hosting

Administratorer kan give overlever-XP eller hele niveauer til eksisterende online- og offlineprofiler. Offline-tildelinger gælder straks. Ryd avancementer frigør pladser uden at refundere AP eller ændre færdigheds-XP. For offlinefigurer afventer rydningen næste forbindelse og kan annulleres indtil da. Ændring af et færdighedsniveau via spillerstatistik rydder den pågældende færdigheds registrering.

SLA bruger Project Zomboids normale gemmesystem. Aktivér SaveWorldEveryMinutes på hostede og dedikerede servere, og luk serveren normalt.

## Kompatibilitet

- **Inkompatibel: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Ikke understøttet i øjeblikket: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) og [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. De erstatter direkte udviklingsregler, som SLA afhænger af.
- **Afhænger af indlæsningsrækkefølgen: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Indlæs SLA efter Detailed Skill Tooltips for at føje SLA's blå indhentningstekst til DST's udvidede færdighedsbeskrivelser. Indlæses SLA først, erstattes kun denne tekst. Overleverniveauets udvikling og +knappernes værktøjstip virker stadig.
- **Testet sammen: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) og [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Kombinationen virkede problemfrit i tests, men kompatibilitet med alle mods til brugerfladen eller modfærdigheder kan ikke garanteres.
- Mods, der erstatter håndtering af færdigheds-XP, lofter eller kurver, færdighedspanelet, spillermenuer eller digitaluret, kan skabe konflikter. SLA deaktiverer den berørte integration, hvis dens nødvendige tilkoblinger erstattes. Kompatible modfærdigheder kræver en brugbar XP-kurve og understøttede XP-hændelser. Direkte ændring af færdigheder eller udvikling uden sådanne hændelser giver ikke overlever-XP.

## Brug af AI

AI blev brugt til at skrive al koden i projektet. Den oprindelige idé, designretning, test, fejlfinding og udgivelsesbeslutninger er mine egne. Jeg har brugt mange timer på personligt at teste SLA og løse problemer, så det fungerer efter hensigten. Foretrækker du at undgå mods udviklet med AI-hjælp, forstår og respekterer jeg det.

## Støtte

- Donationer via [Ko-fi](https://ko-fi.com/skeptic043) er frivillige. Ingen modfunktioner kræver betaling.

## Modoplysninger

- Udviklet/testet på version: 42.20.4
- Påkrævede afhængigheder: Ingen
- Licens: MIT
- [Kildekode og fejlrapportering](https://github.com/Skeptic043/survivor-leveling-and-advancement)
