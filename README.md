# Manabar

WoW Forever addon (Interface 16001), ami a csapatod manahasználóinak a manáját
mutatja egy-egy baron, szerep szerint csoportosítva (a healerek mindig elöl).
Alapból harcon kívül mindenki látszik, harc közben csak a healerek.

## Mit tud

- **Egy bar játékosonként**: a bal oldalon a spec ikonja és a név, a jobb oldalon a mana %-a.
- **Ivás jelzése**: ha valaki iszik (Drink buff), egy pohár ikon és az „Iszik” felirat
  jelenik meg a baron.
- **Színátmenet**: 100%-on zöld, 50%-on sárga, 0%-on piros, közte folyamatos átmenet.
- **Harcon kívül minden manahasználó, harcban csak a healerek**: alapból mindhárom
  szerep (Healer, DPS, Tank) be van pipálva; amint harcba lépsz, a lista a healerekre
  szűkül, harc után pedig visszaáll. Ez a beállításokban kikapcsolható.
- **Szerep fejlécek**: a barok szerep szerint csoportosítva jelennek meg (Healer, DPS,
  Tank, Ismeretlen), mindegyik csoport fölött egy fejléccel: szerep-ikon, név, létszám
  és **a csoport átlag manája**. Ha a játék elrejti a mana értékét (WoW Forever-ben ez a
  megszokott), az átlagot szám nélkül, a fejléc hosszával és színével mutatja; a
  25 / 50 / 75%-os jelek segítenek leolvasni. Ha olvasható, a pontos % is kiíródik.
- **Teljes átlag bar** a lista alján (kikapcsolható): az összes mutatott bar átlaga.
  Fejlécekkel csak akkor jelenik meg, ha több szerep látszik (különben ugyanazt
  mutatná, mint a fejléc).
- **Mozgatható**: feloldott állapotban bal egérgombbal húzható. Rögzítés: jobb klikk
  az ablakon vagy `/manabar lock`.
- **Beállítások ablak** a fogaskerék ikonra kattintva (vagy `/manabar`):
  - harc közben csak a healerek látszanak (alapból be)
  - csak harcon kívül látszik
  - szerep fejlécek (átlaggal)
  - teljes átlag bar a lista alján
  - a saját manád is látszik-e
  - akinek még nem ismert a szerepe, az is látszódjon-e (alapból nem)
  - spec ikon a bar elején
  - ablak rögzítése
  - **kinek a manáját mutassa**: szerep szerint – **Healer**, **DPS**, **Tank**
    (bármelyik kombináció). Alapból mindhárom be van pipálva.
- Offline / halott állapot szürke barral („Offline”, „Halott”).
- Magyar és angol felület (`/manabar lang hu` / `/manabar lang en`).

## Telepítés

1. Töltsd le a repót (GitHubon *Code → Download ZIP*), és csomagold ki.
2. A kicsomagolt mappában lévő **`Manabar`** mappát (amiben a `Manabar.toc` van)
   másold ide:

   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```

   A végeredmény így néz ki: `...\_forever_\Interface\AddOns\Manabar\Manabar.toc`
   (ne legyen dupla mappa, pl. `AddOns\manabar-main\Manabar\...`).
3. Indítsd el a játékot (vagy `/reload`), és a karakterválasztón az *AddOns* gombnál
   ellenőrizd, hogy a Manabar be van-e kapcsolva.

Első indításkor az ablak feloldva, középen jelenik meg: húzd a helyére, majd rögzítsd.

## Parancsok

| Parancs | Mit csinál |
| --- | --- |
| `/manabar` vagy `/manabar config` | beállítások ablak (ugyanaz, mint a fogaskerék) |
| `/manabar lock` / `unlock` | ablak rögzítése / mozgathatóvá tétele |
| `/manabar reset` | pozíció és méret visszaállítása |
| `/manabar scale 1.2` | méretarány (0.5 – 3, tizedesvessző is jó) |
| `/manabar width 220` / `height 20` | bar szélesség (100 – 400) / magasság (12 – 40) |
| `/manabar healers` | harc közben csak a healerek be/ki |
| `/manabar combat` | csak harcon kívül látszik be/ki |
| `/manabar headers` | szerep fejlécek (átlaggal) be/ki |
| `/manabar summary` | teljes átlag bar a lista alján be/ki |
| `/manabar self` | saját mana mutatása be/ki |
| `/manabar add [név]` | valaki mindig látszódjon (név nélkül: a targeted) |
| `/manabar ignore [név]` | valaki soha ne látszódjon |
| `/manabar remove [név]` | törlés a kézi listákról |
| `/manabar list` | kézi listák kiírása |
| `/manabar test` | tesztmód minta healerekkel (pozicionáláshoz, kipróbáláshoz) |
| `/manabar lang hu` / `lang en` | nyelv |
| `/manabar diag` | kiírja, mit enged olvasni a játék (név, kaszt, mana: olvasható vagy `secret`) – harc közben is futtatható, hibabejelentéshez |
| `/manabar debug` | hibakeresési üzenetek be/ki (hibabejelentéshez hasznos) |

## Hogyan dönti el, kit mutasson?

A szűrés a játékos szerepe szerint történik (Healer / DPS / Tank):

1. Kézi listák (`add` / `ignore`) – ezek mindent felülírnak.
2. Csak manát használó kasztok jelenhetnek meg: Warrior és Rogue soha (akkor sem, ha a
   Tank vagy a DPS be van pipálva).
3. A szerep az, amit a csapatban beállítottak (csoportkereső / szerepválasztás).
   Harc közben – ha a „Harc közben csak a healerek látszanak” opció be van kapcsolva –
   a kipipált szerepekből csak a Healer marad.
4. Ha nincs beállított szerep, a spec szerepe dönt: a sajátod mindig ismert, másokét egy
   rövid **inspect** deríti ki (csak harcon kívül, legfeljebb 2 másodpercenként egy
   játékos; előbb azok, akiknél a szerep dönti el, látszanak-e). Ha a kaszt minden
   specje ugyanazt a választ adja (pl. a Mage mindig DPS),
   inspect sem kell. Amíg nem derül ki, az illető **rejtve marad** – ha inkább azonnal
   látni szeretnéd, kapcsold be az „Akinek még nem ismert a szerepe, az is látszik”
   opciót; ilyenkor kérdőjel ikon jelzi, hogy még nem biztos.

A bar elején lévő ikon mutatja, minek (melyik specnek) ismerte fel az addon az illetőt.

## Harc közbeni korlátozások (Midnight „secret values”)

A WoW Forever a Midnight kliensre épül, így az addonokra ugyanazok a szabályok
vonatkoznak: harc közben a játék a többi játékos adatait (pl. manáját) „titkosított”
értékként adhatja át, amivel addon nem számolhat.

- A **barok harc közben is működnek**: a %-ot és a színt a játék saját, erre szolgáló
  curve-függvényei számolják ki, az addon csak továbbadja őket a kijelzőnek. Ha a játék
  az addon saját görbéit elutasítaná, a Blizzard beépített görbéivel, végső esetben a
  nyers mana-számmal működik tovább.
- Harc közben a játék a csapattagok nevét, kasztját is elrejtheti. Ezért harcban a lista
  csak akkor épül újra, ha valaki ki- vagy belép, és ilyenkor is a harc előtt megjegyzett
  adatokkal dolgozik – a barok nem tűnnek el.
- Ha harcban mégsem látszanak a barok: nézd meg, hogy a beállításokban nincs-e bepipálva
  a „Csak harcon kívül látszik”, és harc közben futtasd a `/manabar diag` parancsot.
- Az **átlag** viszont összeadás, azt az addon nem végezheti el titkosított értékeken,
  ezért számot nem tud kiírni. Helyette a játék rajzolja ki: a healerek bar-darabjai
  egymás után kerülnek (mindegyik a teljes szélesség 1/N-ed részén), így a kitöltés hossza
  pontosan az átlag, a színük pedig összeadódik az átlag színére. Az addon közben egyetlen
  értéket sem lát. Amikor a mana olvasható, a pontos % is kiíródik.
- Az **ivás** jelzés harcon kívül működik (harcban úgysem lehet inni).

## Fejlesztőknek

A `tests/` mappában van egy játék nélkül futtatható tesztkészlet: egy szigorú WoW API
szimulátor (`tests/wow_mock.lua`), ami a secret value szabályokat is utánozza, és rá
épülő tesztek (`tests/run_tests.lua`).

```bash
lua5.1 tests/run_tests.lua
```

Fájlok: `Manabar/Locales.lua` (szövegek), `Manabar/Manabar.lua` (barok, logika),
`Manabar/Options.lua` (beállítások ablak).

---

**English:** Manabar shows the mana of your WoW Forever party or raid, grouped by role
(healers always first): by default every mana user out of combat and only the healers
in combat. Each bar has the name, mana %, a drinking indicator and a red → yellow →
green color gradient; each role header shows the role's average mana. Drag it while
unlocked, click the gear icon (or type `/manabar`) for the settings, and use
`/manabar lang en` for English texts. Install by copying the `Manabar` folder into
`World of Warcraft\_forever_\Interface\AddOns\`.
