# Survivor Leveling & Advancement [B42]

Zdobywaj punkty za rozwijanie umiejętności i wydawaj je na wybrane przez siebie umiejętności. SLA dodaje poziom ocalałego i punkty rozwoju do zwykłego panelu umiejętności, zachowując naturalny rozwój. Chcesz, żeby część postępów przetrwała twoją następną złą decyzję? Opcjonalne dziedziczenie poziomów pozwala następnej postaci zachować procent poziomu ocalałego i otrzymać nowe punkty do wydania.

Obsługuje grę jednoosobową, wieloosobową, podzielony ekran i kontroler. Bez wymaganych zależności.

## Jak działa rozwój

XP zdobywane w obsługiwanych umiejętnościach podnosi też poziom ocalałego. Każdy poziom daje jeden punkt rozwoju, czyli AP. Wydawaj AP przyciskami **+** obok umiejętności. Domyślnie można zajmować trzy miejsca rozwoju jednocześnie. Ćwiczenie podniesionej umiejętności zwalnia jej miejsca w miarę zdobywania pominiętego XP. To XP liczy się również do następnego poziomu umiejętności.

Ostatni awans do rzeczywistego maksimum umiejętności, zwykle z poziomu 9 na 10, oznacza jej mistrzowskie opanowanie. Kosztuje 2 AP i wymaga 2 wolnych miejsc rozwoju, po czym zwalnia wszystkie aktywne miejsca tej umiejętności. Jeśli limit Globalny lub Na umiejętność wynosi 1, wystarczy 1 wolne miejsce, ale koszt pozostaje równy 2 AP. Tryb swobodny nie wymaga miejsc i nadal kosztuje 2 AP. Umiejętność na rzeczywistym maksimum nie generuje dodatkowego XP ocalałego.

## Zachowaj część postępów po śmierci

Włącz dziedziczenie poziomu ocalałego i wybierz, ile przejdzie na następną postać w tym samym świecie. Na przykład śmierć na poziomie ocalałego 20 przy dziedziczeniu 50% daje następnej postaci poziom ocalałego 10 i 10 AP do wydania. Stare poziomy umiejętności nie są kopiowane, więc możesz wybrać, na co przeznaczyć odziedziczone punkty. Dziedziczenie jest opcjonalne i domyślnie wyłączone.

## Ustawienia

- **Globalny:** Wszystkie umiejętności korzystają ze wspólnej, konfigurowalnej puli miejsc rozwoju. Domyślny limit wynosi łącznie 3 aktywne miejsca.
- **Na umiejętność:** Każda umiejętność ma własny konfigurowalny limit, z wartością domyślną dla zgodnych dodatkowych umiejętności i opcjonalnymi osobnymi ustawieniami dla umiejętności podstawowej gry.
- **Swobodny:** Usuwa limity miejsc rozwoju i ograniczenia związane z nadrabianiem XP.
- Zmieniaj szybkość zdobywania XP ocalałego bez zmiany XP umiejętności. Wybierz, czy kondycja, siła, poszczególne umiejętności podstawowej gry i zgodne dodatkowe umiejętności mają się liczyć.
- W opcjach modów włącz bardziej kontrastowe znaczniki rozwoju lub procent XP ocalałego gracza 1 na zegarku cyfrowym.
- Obsługuje wszystkie standardowe języki dostępne w ustawieniach języka Project Zomboid. Wszystkie tłumaczenia wykonano w całości przy użyciu AI. Jeśli zauważysz błędny lub niezrozumiały tekst, zgłoś go.

**Uwaga:** Zmiana trybu nie zeruje śledzonych postępów. Naturalne XP umiejętności zdobyte w trybie swobodnym nadal zmniejsza zachowane niebieskie zaległości. Po powrocie do trybu Globalnego lub Na umiejętność przywracana jest tylko pozostała część.

## Dodawanie lub usuwanie SLA

SLA można dodać do istniejącego zapisu i z niego usunąć. Istniejące umiejętności zostają zachowane, a wcześniejsze postępy nie przyznają poziomów ocalałego wstecz. Wyłączenie SLA ukrywa interfejs, lecz zachowuje poziomy umiejętności kupione za AP. Ponowne włączenie przywraca stan SLA i uwzględnia obsługiwane postępy zdobyte podczas jego nieobecności. Jak przy każdej zmianie listy modów, zdecydowanie zalecam tworzenie kopii zapasowych ważnych światów.

## Serwery dedykowane i hostowanie

Administratorzy mogą przyznawać XP ocalałego lub pełne poziomy istniejącym profilom online i offline. Przyznanie offline działa od razu. Czyszczenie awansów zwalnia miejsca bez zwrotu AP i zmiany XP umiejętności. Dla postaci offline pozostaje oczekujące i można je anulować do ponownego połączenia. Zmiana poziomu w statystykach gracza czyści rozliczenie danej umiejętności.

SLA korzysta ze zwykłego zapisywania Project Zomboid. Na serwerach dedykowanych i hostowanych włącz SaveWorldEveryMinutes i zamykaj serwer normalnie.

## Zgodność

- **Niezgodny: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Obecnie nieobsługiwane: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) i [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Te mody bezpośrednio zastępują zasady rozwoju, od których zależy SLA.
- **Zależny od kolejności ładowania: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Załaduj SLA po Detailed Skill Tooltips, aby dodać tekst niebieskich zaległości SLA do rozszerzonych podpowiedzi DST. Jeśli SLA ładuje się wcześniej, zastąpiony zostanie tylko ten tekst. Rozwój ocalałego i podpowiedzi przycisków + nadal działają.
- **Testowane razem: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) i [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Ten zestaw działał bez problemów w testach, ale nie można zagwarantować zgodności z każdym modem interfejsu lub dodatkowych umiejętności.
- Mody zastępujące obsługę XP, limity lub krzywe umiejętności, panel umiejętności, menu graczy lub zegarek cyfrowy mogą powodować konflikty. SLA wyłącza daną integrację po zastąpieniu jej wymaganych punktów podpięcia. Własne umiejętności wymagają użytecznej krzywej XP i obsługiwanych zdarzeń XP. Bezpośrednie zmiany umiejętności lub rozwój bez takich zdarzeń nie dają XP ocalałego.

## Użycie AI

Cały kod tego projektu napisano przy użyciu AI. Pierwotny pomysł, kierunek projektu, testy, usuwanie błędów i decyzje o wydaniu są moje. Spędziłem wiele godzin na osobistym testowaniu SLA i rozwiązywaniu problemów, aby działał zgodnie z założeniami. Jeśli wolisz nie używać modów tworzonych z pomocą AI, rozumiem i szanuję ten wybór.

## Wsparcie

- Wpłaty przez [Ko-fi](https://ko-fi.com/skeptic043) są dobrowolne. Żadna funkcja moda nie wymaga opłaty.

## Informacje o modzie

- Opracowano/testowano na wersji: 42.20.4
- Wymagane zależności: Brak
- Licencja: MIT
- [Kod źródłowy i zgłaszanie problemów](https://github.com/Skeptic043/survivor-leveling-and-advancement)
