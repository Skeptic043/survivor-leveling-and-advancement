# Survivor Leveling & Advancement [B42]

Získávejte body rozvíjením dovedností a utrácejte je za dovednosti podle svého výběru. SLA přidává do běžného panelu dovedností úroveň přeživšího a body vylepšení, přičemž zachovává přirozený rozvoj dovedností. Chcete, aby část pokroku přežila vaše příští špatné rozhodnutí? Volitelné dědění úrovní umožní další postavě převzít procento úrovně přeživšího a získat nové body k utracení.

Podporuje hru jednoho i více hráčů, rozdělenou obrazovku a ovladač. Nevyžaduje další mody.

## Jak vylepšování funguje

XP získané v podporovaných dovednostech zvyšují i úroveň přeživšího. Každá úroveň dává jeden bod vylepšení neboli AP. AP utrácíte tlačítky **+** vedle dovedností. Ve výchozím nastavení můžete současně obsadit tři pozice pro vylepšení. Procvičováním vylepšené dovednosti doplníte přeskočené XP a uvolníte její pozice. Tyto XP zároveň přispívají k další úrovni dovednosti.

Poslední vylepšení na skutečné maximum dovednosti, obvykle z úrovně 9 na 10, znamená její ovládnutí. Stojí 2 AP, vyžaduje 2 volné pozice pro vylepšení a poté uvolní všechny aktivní pozice dané dovednosti. Je-li limit v režimu Společný nebo Podle dovednosti nastaven na 1, stačí 1 volná pozice, ale cena zůstává 2 AP. Volný režim nevyžaduje žádné pozice, cena je stále 2 AP. Dovednost na svém skutečném maximu už nevytváří XP přeživšího.

## Zachovejte část pokroku po smrti

Zapněte dědění úrovně přeživšího a určete, kolik získá další postava ve stejném světě. Pokud například zemřete na úrovni přeživšího 20 s děděním 50%, další postava získá úroveň přeživšího 10 a 10 AP. Původní úrovně dovedností se nekopírují, takže sami rozhodnete, kam zděděné body vložíte. Dědění je volitelné a ve výchozím nastavení vypnuté.

## Nastavení

- **Společný:** Všechny dovednosti sdílejí nastavitelný počet pozic pro vylepšení. Výchozí limit je celkem 3 aktivní pozice.
- **Podle dovednosti:** Každá dovednost má vlastní nastavitelný limit. Kompatibilní přidané dovednosti používají výchozí hodnotu, dovednosti základní hry mohou mít individuální nastavení.
- **Volný:** Odstraňuje limity pozic pro vylepšení a omezení dohánění XP.
- Upravte rychlost získávání XP přeživšího bez změny XP dovedností. Vyberte, zda přispívá kondice, síla, jednotlivé dovednosti základní hry a kompatibilní přidané dovednosti.
- V nastavení modů lze zapnout kontrastnější značky vylepšení nebo procento XP přeživšího hráče 1 na digitálních hodinkách.
- Podporuje všechny standardní jazyky v jazykovém nastavení Project Zomboid. Veškeré překlady vytvořila výhradně AI. Nesprávný nebo nejasný text prosím nahlaste.

**Poznámka:** Změna režimu nemaže zaznamenaný pokrok. Přirozené XP dovedností získané ve Volném režimu dál snižují zachované modré dohánění. Návrat do režimu Společný nebo Podle dovednosti obnoví jen zbývající část.

## Přidání nebo odebrání SLA

SLA lze přidat do existujících her i odebrat. Dovednosti zůstanou zachovány a minulý pokrok nedává zpětně úrovně přeživšího. Vypnutí SLA skryje rozhraní, ale ponechá úrovně dovedností získané za AP. Opětovné zapnutí obnoví stav SLA a zohlední podporovaný pokrok získaný během jeho nepřítomnosti. Jako při každé změně seznamu modů důrazně doporučuji zálohovat rozehrané světy, na kterých vám záleží.

## Dedikované servery a hostování

Správci mohou přidělit XP přeživšího nebo celé úrovně existujícím online i offline profilům. Offline příděly se projeví okamžitě. Vymazat vylepšení uvolní pozice bez vrácení AP či změny XP dovedností. U offline postav tento příkaz čeká na opětovné připojení a do té doby jej lze zrušit. Změna úrovně přes statistiky hráče vymaže evidenci dané dovednosti.

SLA používá běžné ukládání Project Zomboid. Na hostovaných i dedikovaných serverech zapněte SaveWorldEveryMinutes a server vypínejte řádně.

## Kompatibilita

- **Nekompatibilní: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Momentálně nepodporované: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) a [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Tyto mody přímo nahrazují pravidla postupu, na kterých SLA závisí.
- **Závisí na pořadí načítání: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Načtěte SLA po Detailed Skill Tooltips, aby doplnil text modrého dohánění do rozšířených popisků DST. Při načtení SLA jako prvního se nahradí pouze tento text. Postup úrovně přeživšího i popisky tlačítek + fungují dál.
- **Společně otestováno: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) a [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Tato kombinace v testech fungovala bez potíží. Kompatibilitu s každým modem rozhraní či přidaných dovedností však nelze zaručit.
- Mody nahrazující zpracování XP, maxima či křivky dovedností, panel dovedností, nabídky hráče nebo digitální hodinky mohou kolidovat. SLA vypne dotčené propojení, pokud někdo nahradí jeho nezbytné napojení. Kompatibilní přidané dovednosti potřebují použitelnou křivku XP a podporované události XP. Přímé nastavení dovedností či postup bez těchto událostí nevytváří XP přeživšího.

## Použití AI

Veškerý kód tohoto projektu napsala AI. Původní koncept, směr návrhu, testování, ladění a rozhodnutí o vydání jsou moje. Osobním testováním SLA a řešením problémů jsem strávil mnoho hodin, aby fungoval podle záměru. Pokud mody vyvinuté s pomocí AI raději nepoužíváte, chápu a respektuji vaši volbu.

## Podpora

- Příspěvky přes [Ko-fi](https://ko-fi.com/skeptic043) jsou dobrovolné a žádné funkce modu nejsou placené.

## Informace o modu

- Vyvinuto/testováno na verzi: 42.20.4
- Povinné závislosti: žádné
- Licence: MIT
- [Zdrojový kód a hlášení problémů](https://github.com/Skeptic043/survivor-leveling-and-advancement)
