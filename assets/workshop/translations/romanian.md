# Survivor Leveling & Advancement [B42]

Câștigă puncte dezvoltându-ți abilitățile, apoi cheltuiește-le pe cele dorite. SLA adaugă un nivel de supraviețuitor și puncte de avansare în panoul obișnuit de abilități, păstrând progresia naturală. Vrei ca o parte din progres să supraviețuiască următoarei tale decizii proaste? Moștenirea opțională a nivelurilor permite următorului personaj să păstreze un procent din nivelul tău de supraviețuitor, cu puncte noi de cheltuit.

Acceptă joc individual, multiplayer, ecran împărțit și controler. Fără dependențe obligatorii.

## Sistemul de avansare

XP obținute din abilitățile acceptate cresc și nivelul de supraviețuitor. Fiecare nivel oferă un punct de avansare, sau AP. Cheltuiește AP cu butoanele **+** de lângă abilități. Implicit, poți ocupa simultan trei locuri de avansare. Exersarea unei abilități avansate îi eliberează locurile pe măsură ce recuperezi XP sărite. Aceste XP contează și pentru următorul nivel al abilității.

Ultima avansare până la maximul efectiv al abilității, de obicei de la nivelul 9 la 10, înseamnă stăpânirea completă. Costă 2 AP și necesită 2 locuri de avansare libere, apoi eliberează toate locurile active ale acelei abilități. Dacă limita Comun sau Per abilitate este 1, ajunge 1 loc liber, dar costul rămâne 2 AP. Modul Fără limite nu necesită locuri și păstrează costul de 2 AP. O abilitate la maximul efectiv nu mai generează XP de supraviețuitor.

## Păstrează progres după moarte

Activează moștenirea nivelului de supraviețuitor și alege cât primește următorul personaj din aceeași lume. De exemplu, dacă mori la nivelul de supraviețuitor 20 cu moștenire de 50%, următorul personaj primește nivelul de supraviețuitor 10 și 10 AP. Vechile niveluri ale abilităților nu sunt copiate, așa că alegi unde investești punctele moștenite. Moștenirea este opțională și dezactivată implicit.

## Setări

- **Comun:** Toate abilitățile împart un număr configurabil de locuri de avansare, cu o limită implicită de 3 locuri active în total.
- **Per abilitate:** Fiecare abilitate are propria limită configurabilă. Abilitățile personalizate compatibile folosesc o valoare implicită, iar cele din jocul de bază pot avea valori individuale opționale.
- **Fără limite:** Elimină limitele locurilor de avansare și restricțiile de recuperare a XP.
- Reglează viteza XP de supraviețuitor fără să modifici XP ale abilităților. Alege dacă contribuie condiția fizică, forța, fiecare abilitate de bază și abilitățile personalizate compatibile.
- În opțiunile modului, activează marcaje de avansare mai contrastante sau procentul XP de supraviețuitor al jucătorului 1 pe ceasul digital.
- Acceptă toate limbile standard din setările de limbă Project Zomboid. Toate traducerile au fost realizate integral de AI. Te rog să raportezi textele greșite sau neclare.

**Notă:** Schimbarea modului nu resetează progresul înregistrat. XP naturale ale abilităților obținute în Fără limite reduc în continuare recuperarea albastră păstrată. Revenirea la Comun sau Per abilitate restaurează doar partea rămasă.

## Adăugarea sau eliminarea SLA

SLA poate fi adăugat în salvări existente sau eliminat din ele. Abilitățile se păstrează, iar progresul anterior nu acordă retroactiv niveluri de supraviețuitor. Dezactivarea ascunde interfața, dar păstrează nivelurile abilităților obținute cu AP. Reactivarea restaurează starea SLA și ia în calcul progresia acceptată obținută în absența sa. Ca la orice modificare a listei de moduri, recomand insistent o copie de siguranță a lumilor în curs la care ții.

## Servere dedicate și găzduire

Administratorii pot acorda XP de supraviețuitor sau niveluri întregi profilurilor existente, online și offline. Acordările offline se aplică imediat. Șterge avansările eliberează locuri fără să restituie AP sau să modifice XP ale abilităților. Pentru personajele offline, ștergerea rămâne în așteptare și poate fi anulată până la reconectare. Modificarea unui nivel prin statisticile jucătorului șterge evidența abilității respective.

SLA folosește salvările obișnuite Project Zomboid. Pe servere găzduite și dedicate, activează SaveWorldEveryMinutes și oprește serverul normal.

## Compatibilitate

- **Incompatibil: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Momentan neacceptate: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) și [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Aceste moduri înlocuiesc direct regulile de progresie pe care se bazează SLA.
- **Depinde de ordinea încărcării: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Încarcă SLA după Detailed Skill Tooltips pentru a adăuga textul albastru de recuperare SLA la descrierile extinse DST. Dacă SLA se încarcă primul, este înlocuit doar acest text. Progresia nivelului de supraviețuitor și descrierile butoanelor + funcționează în continuare.
- **Testate împreună: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) și [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Combinația a funcționat fără probleme în teste, dar compatibilitatea cu orice mod de interfață sau abilități personalizate nu poate fi garantată.
- Modurile care înlocuiesc gestionarea XP, maximele sau curbele abilităților, panoul de abilități, meniurile jucătorului ori ceasul digital pot crea conflicte. SLA dezactivează integrarea afectată dacă legăturile necesare sunt înlocuite. Abilitățile personalizate compatibile necesită o curbă XP utilizabilă și evenimente XP acceptate. Setarea directă a abilităților sau progresia fără asemenea evenimente nu generează XP de supraviețuitor.

## Folosirea AI

Întregul cod al proiectului a fost scris cu AI. Conceptul original, direcția de proiectare, testarea, depanarea și deciziile de publicare îmi aparțin. Am petrecut multe ore testând personal SLA și rezolvând probleme pentru a mă asigura că funcționează conform intenției. Dacă preferi să nu folosești moduri dezvoltate cu ajutorul AI, înțeleg și respect alegerea ta.

## Susținere

- Donațiile prin [Ko-fi](https://ko-fi.com/skeptic043) sunt opționale. Nicio funcție a modului nu necesită plată.

## Informații despre mod

- Dezvoltat/testat pe versiunea: 42.20.4
- Dependențe obligatorii: Niciuna
- Licență: MIT
- [Cod sursă și raportarea problemelor](https://github.com/Skeptic043/survivor-leveling-and-advancement)
