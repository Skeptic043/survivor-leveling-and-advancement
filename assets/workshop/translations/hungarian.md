# Survivor Leveling & Advancement [B42]

Szerezz pontokat képességeid fejlesztésével, majd költsd őket a választott képességekre. Az SLA túlélőszinttel és fejlesztési pontokkal egészíti ki a szokásos képességpanelt, a természetes fejlődés megtartásával. Szeretnéd, hogy a fejlődésed egy része túlélje a következő rossz döntésedet? Az opcionális szintörökléssel következő karaktered megkapja túlélőszinted egy százalékát és új, elkölthető pontokat.

Támogatja az egyjátékos és többjátékos módot, az osztott képernyőt és a kontrollert. Nincsenek kötelező függőségek.

## A fejlesztés működése

A támogatott képességekből szerzett XP a túlélőszintedet is növeli. Minden túlélőszint egy fejlesztési pontot, azaz AP-t ad. Az AP-t a képességek melletti **+** gombokkal költheted el. Alapból egyszerre három fejlesztési hely lehet foglalt. A fejlesztett képesség gyakorlásával bepótolod az átugrott XP-t, és felszabadítod a helyeit. Ez az XP a következő képességszintbe is beleszámít.

Az utolsó fejlesztés a képesség tényleges maximumára, általában a 9. szintről a 10.-re, teljes elsajátításnak számít. Ára 2 AP, és 2 szabad fejlesztési helyet igényel, majd felszabadítja a képesség összes aktív helyét. Ha a Közös vagy Képességenként mód korlátja 1, csak 1 szabad hely kell, de az ár továbbra is 2 AP. Korlátlan módban nincs szükség helyre, az ár ott is 2 AP. A tényleges maximumon lévő képesség nem termel további túlélő XP-t.

## Őrizz meg fejlődést halál után

Kapcsold be a túlélőszint öröklését, és válaszd ki, mennyit kapjon a következő karaktered ugyanabban a világban. Például ha 20-as túlélőszinten halsz meg 50%-os örökléssel, a következő karaktered 10-es túlélőszintet és 10 AP-t kap. A régi képességszintek nem másolódnak át, így te döntöd el, mire költöd az örökölt pontokat. Az öröklés választható, alapból ki van kapcsolva.

## Beállítások

- **Közös:** Minden képesség egy állítható fejlesztésihely-kereten osztozik. Az alapkorlát összesen 3 aktív hely.
- **Képességenként:** Minden képesség saját, állítható korlátot kap. A kompatibilis egyéni képességek alapértéket használnak, az alapjáték képességeihez külön felülbírálás adható meg.
- **Korlátlan:** Megszünteti a fejlesztési helyek és az XP-bepótlás korlátozásait.
- A túlélő XP sebessége a képesség-XP módosítása nélkül állítható. Kiválaszthatod, hogy az erőnlét, az erő, az alapjáték egyes képességei és a kompatibilis egyéni képességek hozzájáruljanak-e.
- A modbeállításokban kontrasztosabb fejlesztésjelölők vagy az 1. játékos túlélő XP-százaléka kapcsolható be a digitális órán.
- A Project Zomboid nyelvi beállításainak minden szabványos nyelvét támogatja. Minden fordítást teljes egészében AI készített. Kérlek, jelezd a hibás vagy félreérthető szöveget.

**Megjegyzés:** A módváltás nem nullázza a nyilvántartott fejlődést. A Korlátlan módban szerzett természetes képesség-XP továbbra is csökkenti a megőrzött kék bepótlási hátralékot. A Közös vagy Képességenként módra visszaváltva csak a hátralévő rész áll vissza.

## Az SLA hozzáadása és eltávolítása

Az SLA meglévő mentésekhez is hozzáadható, illetve eltávolítható belőlük. A képességek megmaradnak, a korábbi fejlődés nem ad visszamenőleg túlélőszinteket. A kikapcsolás elrejti a felületet, de megtartja az AP-ból szerzett képességszinteket. A visszakapcsolás helyreállítja az SLA állapotát, és elszámolja a távollétében szerzett támogatott fejlődést. Mint minden modlista-változtatásnál, itt is erősen ajánlom a fontos, folyamatban lévő világok biztonsági mentését.

## Dedikált szerverek és hosztolás

Az adminok túlélő XP-t vagy egész szinteket adhatnak meglévő online és offline profiloknak. Az offline juttatások azonnal érvényesülnek. A Fejlesztések törlése felszabadítja a helyeket AP-visszatérítés és a képesség-XP módosítása nélkül. Offline karaktereknél a törlés a visszacsatlakozásig függőben marad és lemondható. A képességszint módosítása a játékosstatisztikákban törli az adott képesség elszámolását.

Az SLA a Project Zomboid szokásos mentéseit használja. Hosztolt és dedikált szerveren kapcsold be a SaveWorldEveryMinutes beállítást, és szabályosan állítsd le a szervert.

## Kompatibilitás

- **Nem kompatibilis: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Jelenleg nem támogatott: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) és [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Ezek közvetlenül lecserélik az SLA által használt fejlődési szabályokat.
- **Betöltési sorrendtől függ: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Az SLA a Detailed Skill Tooltips után töltődjön be, hogy kék bepótlási szövege bekerüljön a DST kibővített képességsúgójába. Ha az SLA töltődik be előbb, csak ez a szöveg íródik felül. A túlélőszint fejlődése és a + gombok súgói tovább működnek.
- **Együtt tesztelve: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) és [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Ez az összeállítás gond nélkül működött a tesztekben, de minden felület- vagy képességmod kompatibilitása nem garantálható.
- Ütközhetnek a képesség-XP kezelését, maximumait vagy görbéit, a képességpanelt, a játékosmenüket vagy a digitális órát lecserélő modok. Az SLA kikapcsolja az érintett integrációt, ha szükséges kapcsolódási pontjait lecserélik. A kompatibilis egyéni képességekhez használható XP-görbe és támogatott XP-események kellenek. Közvetlen képességbeállítás vagy ilyen események nélküli fejlődés nem ad túlélő XP-t.

## AI használata

A projekt teljes kódja AI segítségével készült. Az eredeti ötlet, a tervezési irány, a tesztelés, a hibakeresés és a kiadási döntések az enyémek. Sok órát töltöttem az SLA személyes tesztelésével és a hibák megoldásával, hogy a szándékaim szerint működjön. Ha nem szeretnél AI segítségével fejlesztett modokat használni, megértem és tiszteletben tartom a döntésedet.

## Támogatás

- A [Ko-fi](https://ko-fi.com/skeptic043)-adományok önkéntesek. A mod egyetlen funkciója sem fizetős.

## Modinformációk

- Fejlesztve/tesztelve ezen a verzión: 42.20.4
- Kötelező függőségek: Nincsenek
- Licenc: MIT
- [Forráskód és hibabejelentés](https://github.com/Skeptic043/survivor-leveling-and-advancement)
