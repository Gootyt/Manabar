# Manabar

WoW Forever addon (Interface 16001), ami a csapatod healereinek – vagy bármelyik
kiválasztott kaszt/spec kombinációnak – a manáját mutatja egy-egy baron.

## Mit tud

- **Egy bar játékosonként**: a bal oldalon a spec ikonja és a név, a jobb oldalon a mana %-a.
- **Ivás jelzése**: ha valaki iszik (Drink buff), egy pohár ikon és az „Iszik” felirat
  jelenik meg a baron.
- **Színátmenet**: 100%-on zöld, 50%-on sárga, 0%-on piros, közte folyamatos átmenet.
- **Átlag bar** a lista alján (kikapcsolható): a mutatott barok átlagos manája.
  Csak akkor jelenik meg, ha legalább két bar látszik. Ha a játék elrejti a mana
  értékét (WoW Forever-ben ez a megszokott), szám nélkül, a bar hosszával és színével
  mutatja az átlagot; a 25 / 50 / 75%-os jelek segítenek leolvasni.
- **Mozgatható**: feloldott állapotban bal egérgombbal húzható. Rögzítés: jobb klikk
  az ablakon vagy `/manabar lock`.
- **Beállítások ablak** a fogaskerék ikonra kattintva (vagy `/manabar`):
  - csak harcon kívül látszik
  - átlag bar a lista alján
  - a saját manád is látszik-e
  - akinek még nem ismert a specje, az is látszódjon-e (alapból nem)
  - spec ikon a bar elején
  - ablak rögzítése
  - **kinek a manáját mutassa**: kaszt **és** spec szerint, egy rácsban pipálhatod ki
    (Priest, Paladin, Shaman, Druid, Mage, Warlock, Hunter – mindegyiknél külön a 3 spec).
    A kaszt nevére kattintva az egész sor be/ki kapcsol. Alapból a healer specek vannak
    bepipálva. Gyorsgombok: *Csak healerek*, *Mind*, *Egyik sem*.
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
| `/manabar combat` | csak harcon kívül látszik be/ki |
| `/manabar summary` | átlag bar be/ki |
| `/manabar self` | saját mana mutatása be/ki |
| `/manabar add [név]` | valaki mindig látszódjon (név nélkül: a targeted) |
| `/manabar ignore [név]` | valaki soha ne látszódjon |
| `/manabar remove [név]` | törlés a kézi listákról |
| `/manabar list` | kézi listák kiírása |
| `/manabar test` | tesztmód minta healerekkel (pozicionáláshoz, kipróbáláshoz) |
| `/manabar lang hu` / `lang en` | nyelv |
| `/manabar debug` | hibakeresési üzenetek be/ki (hibabejelentéshez hasznos) |

## Hogyan dönti el, kit mutasson?

A szűrés kaszt **és** spec szerint történik: ha például csak a Frost Mage van bepipálva,
egy Fire Mage nem jelenik meg.

1. Kézi listák (`add` / `ignore`) – ezek mindent felülírnak.
2. Ha a játékos specje ismert (a sajátod mindig, másoké inspect után), csak a
   kipipált specek látszanak.
3. Ha a spec még nem ismert, a csapatszerep (tank / healer / dps) szűkít: pl. Paladin +
   healer szerep = Holy, Priest + dps szerep = Shadow. Ha így is több spec lehetséges,
   és ezek nem egyformán vannak pipálva, az illető **rejtve marad**, amíg egy rövid
   **inspect** ki nem deríti a specjét (csak harcon kívül, legfeljebb 2 másodpercenként
   egy játékos). Ha inkább azonnal látni szeretnéd, kapcsold be a beállításokban az
   „Akinek még nem ismert a specje, az is látszik” opciót – ilyenkor kérdőjel ikon jelzi,
   hogy a spec még nem biztos.

A bar elején lévő ikon mutatja, minek ismerte fel az addon az illetőt.

## Harc közbeni korlátozások (Midnight „secret values”)

A WoW Forever a Midnight kliensre épül, így az addonokra ugyanazok a szabályok
vonatkoznak: harc közben a játék a többi játékos adatait (pl. manáját) „titkosított”
értékként adhatja át, amivel addon nem számolhat.

- A **barok működnek**: a %-ot és a színt a játék saját, erre szolgáló
  curve-függvényei számolják ki, az addon csak továbbadja őket a kijelzőnek.
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

**English:** Manabar shows the mana of the healers (or any class/spec combination you
select) in your WoW Forever party or raid: name, mana %, a drinking indicator, a
red → yellow → green color gradient and an optional average bar. Drag it while
unlocked, click the gear icon (or type `/manabar`) for the settings, and use
`/manabar lang en` for English texts. Install by copying the `Manabar` folder into
`World of Warcraft\_forever_\Interface\AddOns\`.
