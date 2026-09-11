# Survivor Leveling & Advancement [B42]

Ansaitse pisteitä kehittämällä taitojasi ja käytä ne haluamiisi taitoihin. SLA lisää tavalliseen taitopaneeliin selviytyjätason ja kehityspisteet säilyttäen taitojen luonnollisen kehityksen. Haluatko osan edistyksestä säilyvän seuraavan huonon päätöksesi jälkeenkin? Valinnainen tasojen periytyminen antaa seuraavalle hahmollesi osuuden selviytyjätasostasi ja uusia pisteitä käytettäväksi.

Tukee yksinpeliä, moninpeliä, jaettua näyttöä ja peliohjainta. Ei pakollisia riippuvuuksia.

## Miten kehitys toimii

Tuetuista taidoista ansaittu XP kasvattaa myös selviytyjätasoa. Jokainen selviytyjätaso antaa yhden kehityspisteen eli AP:n. Käytä AP-pisteitä taitojen vieressä olevilla **+**-painikkeilla. Oletuksena käytössä voi olla kolme kehityspaikkaa kerrallaan. Kehitetyn taidon harjoittelu vapauttaa sen paikat, kun ansaitset ohitetut XP:t. Sama XP vie myös kohti taidon seuraavaa tasoa.

Viimeinen kehitys taidon todelliseen enimmäistasoon, yleensä tasolta 9 tasolle 10, tarkoittaa mestaruutta. Se maksaa 2 AP ja vaatii 2 vapaata kehityspaikkaa. Tämän jälkeen kaikki taidon käytössä olevat kehityspaikat vapautuvat. Jos Yhteinen- tai Taitokohtainen-tilan raja on 1, mestaruus vaatii vain 1 vapaan paikan mutta maksaa yhä 2 AP. Vapaa-tilassa paikkoja ei tarvita, mutta hinta on edelleen 2 AP. Enimmäistasolla oleva taito ei enää tuota selviytyjä-XP:tä.

## Säilytä edistystä kuoleman jälkeen

Ota selviytyjätason periytyminen käyttöön ja valitse, kuinka paljon siirtyy seuraavalle hahmollesi samassa maailmassa. Jos kuolet selviytyjätasolla 20 ja periytyminen on 50%, seuraava hahmosi saa selviytyjätason 10 ja 10 AP. Vanhoja taitotasoja ei kopioida, joten voit itse valita, mihin perityt pisteet käytät. Periytyminen on valinnaista ja oletuksena pois käytöstä.

## Asetukset

- **Yhteinen:** Kaikki taidot jakavat säädettävän kehityspaikkamäärän. Oletusraja on yhteensä 3 aktiivista paikkaa.
- **Taitokohtainen:** Jokaisella taidolla on oma säädettävä rajansa. Yhteensopivat moditaidot käyttävät oletusarvoa, ja peruspelin taidoille voi määrittää omat arvot.
- **Vapaa:** Poistaa kehityspaikkarajat ja ohitetun XP:n kiinniottamiseen liittyvät rajoitukset.
- Säädä selviytyjä-XP:n kertymisnopeutta muuttamatta taito-XP:tä. Valitse, kerryttävätkö kunto, voima, yksittäiset peruspelin taidot ja yhteensopivat moditaidot sitä.
- Modiasetuksista voit ottaa käyttöön selkeämmin erottuvat kehitysmerkit tai pelaajan 1 selviytyjä-XP:n prosenttiluvun digitaalikellossa.
- Tukee kaikkia Project Zomboidin kieliasetusten vakiokieliä. Kaikki käännökset on tehty kokonaan tekoälyllä. Ilmoitathan virheellisestä tai epäselvästä tekstistä.

**Huom:** Tilan vaihtaminen ei nollaa kirjattua edistystä. Vapaa-tilassa ansaittu luonnollinen taito-XP vähentää yhä säilytettyä sinistä kiinniotettavaa XP:tä. Paluu Yhteinen- tai Taitokohtainen-tilaan palauttaa vain jäljellä olevan osuuden.

## SLA:n lisääminen tai poistaminen

SLA:n voi lisätä olemassa oleviin tallennuksiin tai poistaa niistä. Taidot säilyvät, eikä aiempi edistys anna selviytyjätasoja takautuvasti. Käytöstä poistaminen piilottaa käyttöliittymän mutta säilyttää AP:llä hankitut taitotasot. Uudelleenkäyttöönotto palauttaa SLA:n tilan ja huomioi poissaolon aikana kertyneen tuetun edistyksen. Kuten aina modilistaa muuttaessa, suosittelen lämpimästi tärkeiden keskeneräisten maailmojen varmuuskopiointia.

## Erillispalvelimet ja isännöinti

Ylläpitäjät voivat antaa selviytyjä-XP:tä tai kokonaisia tasoja olemassa oleville profiileille myös pelaajan ollessa poissa. Poissa olevien saamat lisäykset tulevat voimaan heti. Tyhjennä kehitykset vapauttaa paikat palauttamatta AP:tä tai muuttamatta taito-XP:tä. Poissa olevan hahmon tyhjennys odottaa seuraavaa yhdistämistä ja on siihen asti peruttavissa. Taitotason muokkaaminen pelaajatilastoista tyhjentää kyseisen taidon kirjanpidon.

SLA käyttää Project Zomboidin tavallisia tallennuksia. Ota SaveWorldEveryMinutes käyttöön isännöidyillä ja erillispalvelimilla ja sulje palvelin normaalisti.

## Yhteensopivuus

- **Yhteensopimaton: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Ei tällä hetkellä tuettu: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) ja [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Nämä modit korvaavat suoraan SLA:n tarvitsemia kehityssääntöjä.
- **Riippuu latausjärjestyksestä: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Lataa SLA Detailed Skill Tooltipsin jälkeen, jotta SLA:n sininen kiinniottoteksti lisätään DST:n laajennettuun taitovihjeeseen. Jos SLA latautuu ensin, vain tämä teksti korvautuu. Selviytyjätason kehitys ja +painikkeiden vihjeet toimivat edelleen.
- **Testattu yhdessä: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) ja [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Yhdistelmä toimi testeissä ongelmitta, mutta yhteensopivuutta kaikkien käyttöliittymä- ja taitomodien kanssa ei voida taata.
- Taito-XP:n käsittelyn, enimmäistasot tai käyrät, taitopaneelin, pelaajavalikot tai digitaalikellon korvaavat modit voivat aiheuttaa ristiriitoja. SLA poistaa kyseisen integraation käytöstä, jos sen tarvitsemat kytkennät korvataan. Yhteensopivat moditaidot tarvitsevat käyttökelpoisen XP-käyrän ja tuetut XP-tapahtumat. Taitojen suora asettaminen tai kehitys ilman näitä tapahtumia ei tuota selviytyjä-XP:tä.

## Tekoälyn käyttö

Projektin kaikki koodi on kirjoitettu tekoälyllä. Alkuperäinen idea, suunnittelun suunta, testaus, virheiden selvitys ja julkaisupäätökset ovat omiani. Olen käyttänyt paljon tunteja SLA:n henkilökohtaiseen testaamiseen ja ongelmien ratkomiseen, jotta se toimisi tarkoitetusti. Jos et halua käyttää tekoälyn avulla kehitettyjä modeja, ymmärrän ja kunnioitan valintaasi.

## Tukeminen

- [Ko-fi](https://ko-fi.com/skeptic043)-lahjoitukset ovat vapaaehtoisia. Yksikään modin ominaisuus ei vaadi maksua.

## Modin tiedot

- Kehitetty/testattu versiolla: 42.20.4
- Pakolliset riippuvuudet: Ei ole
- Lisenssi: MIT
- [Lähdekoodi ja ongelmailmoitukset](https://github.com/Skeptic043/survivor-leveling-and-advancement)
