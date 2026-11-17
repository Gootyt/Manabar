# Manabar

WoW Forever addon (Interface 16001), ami a csapatod healereinek – vagy bármelyik
kiválasztott kaszt/spec kombinációnak – a manáját mutatja egy-egy baron.

## Mit tud

- **Egy bar játékosonként**: a bal oldalon a név, a jobb oldalon a mana %-a.
- **Ivás jelzése**: ha valaki iszik (Drink buff), egy pohár ikon és az „Iszik” felirat
  jelenik meg a baron.
- **Színátmenet**: 100%-on zöld, 50%-on sárga, 0%-on piros, közte folyamatos átmenet.
- **Átlag bar** a lista alján (kikapcsolható): a mutatott barok átlagos manája.
  Csak akkor jelenik meg, ha legalább két bar látszik.
- **Mozgatható**: feloldott állapotban bal egérgombbal húzható. Rögzítés: jobb klikk
  az ablakon vagy `/manabar lock`.
- **Beállítások ablak** a fogaskerék ikonra kattintva (vagy `/manabar`):
  - csak harcon kívül látszik
  - átlag bar a lista alján
  - a saját manád is látszik-e
  - ablak rögzítése
  - **kinek a manáját mutassa**: kaszt/spec rácsban pipálhatod ki (Priest, Paladin,
    Shaman, Druid, Mage, Warlock, Hunter). Alapból a healer specek vannak bepipálva.
    Gyorsgombok: *Csak healerek*, *Mind*, *Egyik sem*.
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

1. Kézi listák (`add` / `ignore`) – ezek mindent felülírnak.
2. Ha a játékos specje ismert (a sajátod mindig, másoké inspect után), a beállítások
   ablakban kipipált spec dönt.
3. Ha a spec még nem ismert, a kaszt és a csapatszerep (tank / healer / dps) alapján
   dönt. Ha ez nem egyértelmű (pl. szerep nélküli Druid, vagy csak a Frost Mage van
   bepipálva), az illető addig látszik, amíg az addon egy rövid **inspecttel** ki nem
   deríti a specjét. Inspect csak harcon kívül történik, legfeljebb 2 másodpercenként
   egy, és csak annál, akinél tényleg számít.

## Harc közbeni korlátozások (Midnight „secret values”)

A WoW Forever a Midnight kliensre épül, így az addonokra ugyanazok a szabályok
vonatkoznak: harc közben a játék a többi játékos adatait (pl. manáját) „titkosított”
értékként adhatja át, amivel addon nem számolhat.

- A **barok harc közben is működnek**: a %-ot és a színt a játék saját, erre szolgáló
  curve-függvényei számolják ki, az addon csak továbbadja őket a kijelzőnek.
- Az **átlag** viszont valódi számolás, ezért ha a játék harc közben titkosítja a
  manát, az átlag baron `?` látszik, amíg az értékek újra olvashatók nem lesznek.
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
