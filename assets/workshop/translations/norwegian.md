# Survivor Leveling & Advancement [B42]

Tjen poeng ved å utvikle ferdighetene dine, og bruk dem på ferdighetene du velger. SLA legger til overlevernivå og avansementspoeng i det vanlige ferdighetspanelet, samtidig som naturlig ferdighetsutvikling beholdes. Vil du at noe av fremgangen skal overleve den neste dårlige avgjørelsen din? Valgfri nivåarv lar den neste figuren beholde en prosentandel av overlevernivået ditt, med nye poeng å bruke.

Støtter enspiller, flerspiller, delt skjerm og kontroller. Ingen påkrevde avhengigheter.

## Slik fungerer avansement

XP fra støttede ferdigheter øker også overlevernivået ditt. Hvert overlevernivå gir ett avansementspoeng, eller AP. Bruk AP med **+**-knappene ved ferdighetene. Som standard kan tre avansementsplasser være opptatt samtidig. Øv på en avansert ferdighet for å tjene inn XP-ene du hoppet over og frigjøre plassene dens. Disse XP-ene teller også mot ferdighetens neste nivå.

Det siste avansementet til en ferdighets faktiske maksimum, vanligvis fra nivå 9 til 10, regnes som mestring. Det koster 2 AP og krever 2 ledige avansementsplasser, og frigjør deretter alle aktive plasser på ferdigheten. Er grensen for Felles eller Per ferdighet satt til 1, krever mestring bare 1 ledig plass, men koster fortsatt 2 AP. Fri krever ingen plasser og koster fortsatt 2 AP. En ferdighet på sitt faktiske maksimum gir ikke flere overlever-XP.

## Behold fremgang etter døden

Aktiver arv av overlevernivå og velg hvor mye den neste figuren i samme verden får. Dør du for eksempel på overlevernivå 20 med 50% arv, får neste figur overlevernivå 10 og 10 AP. De gamle ferdighetsnivåene kopieres ikke, så du velger selv hvor de arvede poengene brukes. Arv er valgfritt og avslått som standard.

## Innstillinger

- **Felles:** Alle ferdigheter deler en justerbar pott med avansementsplasser, med en standardgrense på totalt 3 aktive plasser.
- **Per ferdighet:** Hver ferdighet har sin egen justerbare grense. Kompatible modferdigheter bruker en standardverdi, og grunnspillets ferdigheter kan ha egne overstyringer.
- **Fri:** Fjerner plassgrenser og begrensninger for å tjene inn XP du har hoppet over.
- Juster hastigheten på overlever-XP uten å endre ferdighets-XP. Velg om kondisjon, styrke, enkelte grunnferdigheter og kompatible modferdigheter bidrar.
- Aktiver avansementsmarkører med høyere kontrast eller spiller 1s overlever-XP i prosent på digitalklokken under modinnstillinger.
- Støtter alle standardspråk i Project Zomboids språkinnstillinger. Alle oversettelsene er laget utelukkende med KI. Meld gjerne fra om feil eller uklar tekst.

**Merk:** Bytte av modus nullstiller ikke registrert fremgang. Naturlige ferdighets-XP tjent i Fri reduserer fortsatt den bevarte blå innhentingen. Bytter du tilbake til Felles eller Per ferdighet, gjenopprettes bare det som gjenstår.

## Legge til eller fjerne SLA

SLA kan legges til i og fjernes fra eksisterende lagrede spill. Ferdigheter beholdes, og tidligere fremgang gir ikke overlevernivåer med tilbakevirkende kraft. Deaktivering skjuler grensesnittet, men beholder ferdighetsnivåer kjøpt med AP. Aktivering igjen gjenoppretter SLA-tilstanden og tar hensyn til støttet fremgang tjent mens SLA var borte. Som ved enhver endring av modlisten anbefaler jeg sterkt å sikkerhetskopiere pågående verdener du vil ta vare på.

## Dedikerte servere og vertsspill

Administratorer kan gi overlever-XP eller hele nivåer til eksisterende profiler, både tilkoblede og frakoblede. Tildelinger til frakoblede gjelder straks. Tøm avansementer frigjør plasser uten å refundere AP eller endre ferdighets-XP. For frakoblede figurer venter tømmingen til de kobler til igjen, og kan avbrytes frem til da. Endring av et ferdighetsnivå via spillerstatistikk tømmer regnskapet for den ferdigheten.

SLA bruker Project Zomboids vanlige lagring. Aktiver SaveWorldEveryMinutes på vertsbaserte og dedikerte servere, og avslutt serveren på vanlig måte.

## Kompatibilitet

- **Uforenlig: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Foreløpig ikke støttet: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) og [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Disse erstatter direkte utviklingsregler som SLA avhenger av.
- **Avhenger av lastrekkefølgen: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Last SLA etter Detailed Skill Tooltips for å legge SLAs blå innhentingstekst til DSTs utvidede ferdighetsverktøytips. Lastes SLA først, erstattes bare denne teksten. Overlevernivåets utvikling og verktøytipsene for +knappene fungerer fortsatt.
- **Testet sammen: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) og [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Kombinasjonen fungerte problemfritt i testene, men kompatibilitet med alle grensesnitt- og ferdighetsmoder kan ikke garanteres.
- Moder som erstatter håndtering av ferdighets-XP, grenser eller kurver, ferdighetspanelet, spillermenyer eller digitalklokken, kan skape konflikter. SLA deaktiverer berørt integrasjon hvis nødvendige tilkoblinger erstattes. Kompatible modferdigheter trenger en brukbar XP-kurve og støttede XP-hendelser. Direkte innstilling av ferdigheter eller utvikling uten slike hendelser gir ikke overlever-XP.

## Bruk av KI

KI ble brukt til å skrive all koden i prosjektet. Den opprinnelige ideen, designretningen, testingen, feilsøkingen og utgivelsesbeslutningene er mine egne. Jeg har brukt mange timer på å teste SLA selv og løse problemer slik at det fungerer som tiltenkt. Foretrekker du å unngå moder utviklet med KI-hjelp, forstår og respekterer jeg valget ditt.

## Støtte

- Donasjoner via [Ko-fi](https://ko-fi.com/skeptic043) er frivillige. Ingen modfunksjoner krever betaling.

## Modinformasjon

- Utviklet/testet på versjon: 42.20.4
- Påkrevde avhengigheter: Ingen
- Lisens: MIT
- [Kildekode og feilrapportering](https://github.com/Skeptic043/survivor-leveling-and-advancement)
