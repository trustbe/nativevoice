# NativeVoice — návrh

*Spec pro veřejný přepis projektu MyVoiceInput. Psáno česky pro revizi;
výsledný kód, dokumentace i web budou anglicky.*

## Proč

Dnešní MyVoiceInput funguje a je odladěný dvaceti vydáními, ale vznikl jako
osobní utilitka. Má být zveřejněn **jako ukázka práce**. Z toho plyne všechno
ostatní: rozhoduje první dojem, čitelnost a důvěryhodnost, ne délka seznamu
funkcí.

### Pozice

> **Voice input for the rest of us.**

Diktování pro jazyky, které hlavní nástroje odbývají. Doloženo měřením, ne
tvrzením:

- **macOS má z 54 jazyků plnou podporu diktování — offline model, automatickou
  interpunkci a průběžný poslech — přesně pro jeden.** Pro `en-US`.
- **Wispr Flow mezi vyjmenovanými jazyky češtinu nemá**, přestože polštinu,
  ruštinu i ukrajinštinu ano.
- **ElevenLabs Scribe v2 řadí do nejvyššího pásma (≤5 % WER)** češtinu,
  slovenštinu, polštinu, maďarštinu, rumunštinu, chorvatštinu, ukrajinštinu,
  řečtinu a finštinu.

Druhý pilíř: **otevřený kód znamená, že si uživatel může ověřit, co se děje
s jeho hlasem a jeho klíčem.** U diktovací aplikace je to nejsilnější argument,
jaký existuje — a je ověřitelný, ne slibovaný.

Třetí: je to **jednoduché a levné**. Jedna klávesa, žádné účty navíc, uživatel
platí přímo ElevenLabs a **vlastní spotřebu vidí přímo v aplikaci**.

### Cena — konkrétně

Sazba ElevenLabs je **$0,22 za hodinu zvuku**. Spočítáno:

| používání | denně | měsíčně |
|---|---|---|
| 5 minut | 1,8 centu | $0,40 |
| 15 minut | 5,5 centu | $1,21 |
| 30 minut | 11 centů | $2,42 |
| hodina | 22 centů | $4,84 |

Jedna desetivteřinová věta stojí **šest setin centu**. „Pár centů denně" je
tedy přesné, ne reklamní — a pro běžné diktování je cena prakticky nulová.

### Čím to doložit

Není to produkt na prodej, je to otevřený projekt — README tedy nic netvrdí,
jen ukazuje a odkazuje. Čísla, o která se opírá:

- macOS má plnou podporu diktování pro 1 z 54 jazyků *(změřeno na systému)*
- Wispr Flow mezi vyjmenovanými jazyky češtinu nemá *(jejich stránka)*
- Scribe řadí **36 jazyků do pásma ≤5 % WER**, mezi nimi běloruštinu,
  makedonštinu, islandštinu, galicijštinu, lotyštinu i malajálamštinu —
  tedy malé jazyky ve stejném pásmu jako angličtinu
  *(údaj výrobce, označit jako takový)*
- **Na stejné nahrávce prohrál se Scribe i model doladěný přímo na češtinu.**
  `inferRouter/qwen3-asr-cs-1.7b` podle tabulky svých autorů poráží
  Whisper large-v3 na ParCzech (3,43 vs 5,76) i VoxPopuli (9,79 vs 13,70).
  Na našem vzorku přesto: `ISDS → HZS`, `Fakturoid → faktury`,
  `Cloudflare Worker → cloud forward`, `safetensors → Segmentation`.
  Scribe všechno trefil. *(vlastní měření, jeden vzorek, jeden hlas)*
- $0,22 za hodinu zvuku *(ceník)*
- **TongueType**, nejbližší konkurent na macOS (lokální Whisper, press-to-talk),
  uvádí **12 jazyků**. Scribe má 36 v pásmu do 5 % chybovosti. *(jejich stránka)*

Tohle je nejsilnější doklad, který projekt má, a stojí za to ho v README
rozvést: **specializovaný český model prohrál s univerzálním.** Je to vlastní
měření, ne údaj výrobce, a dá se zopakovat — nahrávka i postup jsou popsané.

Hranice toho tvrzení se uvedou hned vedle, ne drobným písmem: jeden vzorek,
jeden hlas, a Qwen běžel přes obejití (procesor ze základního repozitáře),
takže to nemusí být jeho strop. Netestovali jsme Wispr Flow, Willow ani
cloudové služby Googlu a Microsoftu.

Jediné, na co si dát pozor: **WER od různých výrobců se neporovnává.**
ElevenLabs naměřil Whisperu na FLEURS 14,4 %, inferRouter témuž modelu 12,10 %.
Uvádět je vedle sebe jako žebříček by bylo zavádějící.

### Co se neříká

Konkrétní čísla z účtu autora do veřejných textů nepatří. Cena se uvádí jako
sazba; skutečnou spotřebu si každý uvidí u sebe.

## Rozsah v1

Nový repozitář bez historie. Přepis načisto **včetně pěti funkcí najednou** —
vědomé rozhodnutí zadavatele; výhrada, že se tím míchá přepis s novými
funkcemi a hůř se pak hledá příčina chyb, byla vyslovena a přijata.

| Oblast | Obsah |
|---|---|
| Jádro | podržení klávesy → nahrávání → přepis → vložení pod kurzor |
| Panel | osciloskop skutečné hladiny, stavy, **chyby přímo v panelu** |
| Historie | **volitelná, výchozí vypnutá**; jen text, nastavitelný strop počtu, kliknutím zpět do schránky |
| Délka nahrávky | **nastavitelný strop**, po jeho dosažení se nahrávka uzavře a přepíše |
| Spouštěcí klávesa | **volitelná** z modifikátorů |
| Jazyk přepisu | **volitelný**, výchozí podle jazyka systému |
| Rozhraní | podle jazyka systému, základ angličtina |
| Slovník | **prázdný**, s příkladem v komentáři |
| Spotřeba | jen za převod řeči na text, ne celý účet |
| Aktualizace | z veřejného kanálu, s ověřením podpisu |
| Klíč | v Klíčence, zadává se v aplikaci |

### Mimo rozsah v1

- Realtime přepis přes WebSocket. Latence 1,5–2,5 s je přijatelná a realtime
  by omezil slovník z 1000 výrazů na 50.
- Jiné enginy než ElevenLabs. Rozhraní bude připravené, implementace jedna.
- Diarizace, překlad, titulky.

## Architektura

```
Sources/
  App/            vstupní bod, menu, nastavení
  Input/          odchytávání klávesy
  Audio/          nahrávání a měření hladiny
  Transcription/  rozhraní + klient ElevenLabs
  UI/             panel, graf hladiny
  Update/         aktualizace
  Support/        Klíčenka, log, lokalizace
Tests/
```

Dnešních 1 600 řádků je v šesti souborech, z toho 729 v jediném. Rozdělení
podle odpovědností je u ukázky práce to nejviditelnější zlepšení.

**`Transcription` se dělí na rozhraní a klienta.** To není akademické: u
projektu, jehož hlavní argument je „ověř si, co se děje s tvým hlasem", je
právě tohle místo, kam se čtenář podívá první. Rozhraní zároveň umožní testy
bez sítě.

### Zásady, které se v přepisu nesmí ztratit

Vzniklo to z dvaceti vydání a šesti revizí kódu. Každá z těchto věcí řeší
konkrétní pozorovanou chybu:

- **Tap poslouchá jen `flagsChanged`, nikdy `keyDown`.** Verze s `keyDown`
  v masce se časově shodovala s tím, že přestaly fungovat všechny klávesové
  zkratky v systému. Mechanismus nebyl prokázán, rozdíl byl reprodukovaný.
- **Stav stisku se odvozuje ze zařízeního bitu v události**, ne z vlastního
  příznaku. Jinak se po ztracené události přečte puštění jako stisk.
- **Zvukový řetěz se rozjíždí při stisku, zapisuje až po prahu.** Jinak se
  ukrajuje víc než vteřina na začátku každé věty.
- **Nahrává se v aplikaci, ne podprocesem.** ffmpegu trvalo otevření zařízení
  přes vteřinu.
- **Stažená aktualizace se ověřuje requirementem proti certifikátu**, ne
  hledáním podřetězce ve výstupu `codesign`.
- **Záloha při výměně aplikace leží mimo dočasnou složku.**
- **API klíč se předává rourou, ne argumentem procesu.**
- **Panel je na `CGShieldingWindowLevel()`** — nižší úrovně nestačí nad
  vlastním fullscreenem terminálů.
- **Zápis do logu je serializovaný.**

## Lokalizace

Dvě různé věci, které se nesmí plést:

**Jazyk přepisu** — nabídne se **celé nejvyšší pásmo Scribe, všech 36 jazyků**:

```
bel bos bul cat hrv ces dan nld eng est fin fra glg deu ell hun isl ind
ita jpn kan lav mkd msa mal nor pol por ron rus slk spa swe tur ukr vie
```

(Dokumentace v souhrnu uvádí 34, ve vyjmenovaném seznamu jich je 36.
Rozdíl nevysvětlen, řídíme se seznamem.)

**Seznam se nezužuje.** Je v něm běloruština, bosenština, makedonština,
islandština, galicijština, lotyština, estonština, kannadština i malajálamština —
tedy přesně ty jazyky, kvůli kterým projekt vzniká. Vyřadit je by znamenalo
popřít jeho smysl. Právě to, že Scribe má malé jazyky ve stejném pásmu
přesnosti jako angličtinu, je ten doložený rozdíl proti ostatním nástrojům.

Výchozí podle jazyka systému, když je v seznamu; jinak angličtina. Řazení
abecedně podle názvu v jazyce rozhraní, **bez „oblíbených" nahoře** —
zvýhodnění velkých jazyků by to sdělení oslabilo.

Pásma pod tím (High do 10 %, Good do 20 %, Moderate do 50 %) se v nabídce
neobjeví. Diktování s pětinovou chybovostí není použitelné a nabízet ho by
znamenalo slibovat něco, co neunese.

**Jazyk rozhraní** — **ve v1 jen angličtina.** Aparát bude postavený úplně
(String Catalog, žádné řetězce natvrdo), takže přidat jazyk znamená přidat
soubor — ale dodávat se bude jen to, co umíme ověřit.

Rozhraní má pár desítek krátkých řetězců a jeho jazyk není to, co projekt
řeší; **jazyk přepisu ano.** Překlady rozhraní se budou brát pull requesty,
postup popíše `CONTRIBUTING`.

Technicky: String Catalog (`.xcstrings`), žádné řetězce natvrdo v kódu.

## Slovník vlastních výrazů

Nejúčinnější nástroj na kvalitu, jaký aplikace má — a podle měření **větší
skok než výměna modelu.** Na stejné nahrávce, jediný rozdíl byl slovník:

| výraz | bez slovníku | se slovníkem |
|---|---|---|
| Journeyman | German | ✓ |
| Cloudflare Worker | Cloud for Work | ✓ |
| safetensors | Sage Sensor | ✓ |
| D1 | Z1 | ✓ |
| WER | R | ✓ |

Funguje proto, že vlastní jména a odborné termíny jsou **konečný známý seznam**.
Technicky `keyterms` v API, batch až 1000 položek po 50 znacích.

**Výchozí obsah: prázdný**, jen s vysvětlujícím komentářem. Dnešní slovník
jmenuje klienty autora a do veřejného projektu nepatří. Uživatel si tam doplní
své vlastní.

V rozhraní: položka otevře textový soubor, jeden výraz na řádek, komentáře
mřížkou. Čte se při každém přepisu, takže změna platí okamžitě bez restartu.
V README to patří mezi první, co se vysvětlí — bez slovníku si uživatel
pomyslí, že aplikace komolí jména, a nedozví se, že to má v ruce.

## Jména a adresy

| | |
|---|---|
| Aplikace | **NativeVoice** |
| Podtitulek | *Voice input for the rest of us* |
| Repozitář | `trustbe/nativevoice` |
| Web | **nativevoice.trustbe.com** |
| Bundle ID | `com.trustbe.nativevoice` |
| Repozitář pro vydání | **žádný** |

Jméno nese „vlastní jazyk" a „mluvíš"; že výstupem je text, dovysvětlí
podtitulek. Žádné dvouslovné jméno neunese všechny tři věci najednou.

**Oddělený repozitář pro vydání odpadá.** `MyVoiceInput-releases` existoval
jen proto, že zdrojový repozitář byl privátní a GitHub vracel na vydání 404.
U veřejného projektu si aktualizace berou vydání přímo z hlavního repozitáře —
o jeden projekt a jeden krok ve vydávání méně.

Bundle ID přechází z `cz.nextup` na `com.trustbe`, aby patřilo k doméně.

**Potřeba od majitele domény:** jeden DNS záznam u `trustbe.com` —
`nativevoice CNAME trustbe.github.io`. Zbytek (soubor `CNAME` v repozitáři,
zapnutí Pages, certifikát) obstará nastavení GitHubu.

## Ikona

![návrh ikony](../../design/icon-concept.png)

**Mikrofon, nad ním oblouk sedmi diakritických znamének.** Z dálky to vypadá
jako zvuk vycházející z mikrofonu, zblízka jsou to znaky, které mainstreamové
nástroje komolí. Ikona tak řekne „hlas" i „jazyky, na které ostatní nestačí"
dřív, než si kdokoli přečte jediné slovo.

Použité znaky jsou záměrně z různých jazykových rodin — žádný z nich
angličtina nemá:

| | |
|---|---|
| ˚ kroužek | čeština (ů), švédština (å) |
| ˘ oblouček | rumunština, turečtina |
| ´ čárka | čeština, polština, maďarština, španělština |
| ˇ háček | čeština, slovenština, chorvatština |
| ¨ přehláska | němčina, finština, maďarština |
| ~ vlnovka | španělština, portugalština, estonština |
| ˝ dvojčárka | maďarština (ő, ű) |

Sedm různých znaků se nedá přečíst jinak než „tohle umí spoustu jazyků".
Pět už by mohlo působit jako dekorace.

### Malé velikosti se kreslí zvlášť

Zmenšená velká ikona se ve 32 px slije — ověřeno, ze znaků zbude kaše
a mikrofon je nečitelně malý. Sada je proto **tři různé kresby**, ne jedna
zmenšovaná:

| velikost | kresba |
|---|---|
| 512, 256, 128 | mikrofon + **sedm** znaků, přechod na pozadí |
| 64, 32 | mikrofon + **dva** znaky (háček, čárka), **plochá barva**, silnější tahy |
| 16 | **jen mikrofon**, větší a tučnější |

Proč ty tři stupně:

- **přechod se ve 32 px zašpiní**, proto plochá barva
- **tenké tahy zmizí**, proto jsou v malé kresbě v poměru silnější
- **ve 16 px se i jediný háček slije s mikrofonem** do útvaru, který se čte
  jako „Y" — ověřeno, proto se tam znak vypouští úplně

Náhledy: [32 px](../../design/icon-32.png), [16 px](../../design/icon-16.png),
kresba v [`icon-small.swift`](../../design/icon-small.swift).

Kresba je programová (`docs/design/icon-concept.swift`), ne obrázek —
generuje se do všech velikostí při sestavení. Žádná cizí ikona se nepoužívá.

## Dodržení Apple Human Interface Guidelines

U ukázky práce na macOS je tohle první, čeho si znalý člověk všimne. Konkrétní
body, ne obecné „držet se guidelines":

**Mřížka ikony.** Kresba zabírá **824 z 1024 px (80,5 %)**, okraj kolem
zhruba 100 px. Stávající ikona má okraj 6 %, tedy kresbu na 88 % — **v Docku
by byla viditelně větší než všechny ostatní aplikace.** Je to častá chyba,
u cizích projektů se na ni zakládají issues. Náčrty ikony výše mají tutéž vadu
a při implementaci se přepočítají.

**Ikona v liště.** Dnes jsou to textové znaky `○`, `● REC`, `⋯`. Správně jsou
to **SF Symbols jako template image** — ty se samy přizpůsobí světlé i tmavé
liště a zvýraznění při otevřeném menu. Textové znaky to neumí.

**Okno nastavení.** Menu se postupně změnilo v ovládací panel: jazyk, klávesa,
stropy, slovník, zvuky, vkládání. Podle guidelines patří nastavení do
**samostatného okna otevíraného ⌘,**, v menu zůstanou jen úkony a stav.

**Oznámení.** `NSUserNotification` je zastaralé od macOS 11 a při překladu to
hlásí varování. Nahradit frameworkem `UserNotifications`.

**Přístupnost.** Respektovat *Omezit pohyb* (animace panelu) a *Omezit
průhlednost* (rozostřené pozadí) — obojí jsou systémová nastavení pro lidi,
kterým animace a průhlednost vadí. Doplnit popisky pro VoiceOver na položku
v liště i na panel.

**Psaní v menu.** Velká písmena podle macOS konvence (*Check for Updates*,
ne *Check for updates*), tři tečky jen u položek otevírajících další okno.

## Build a distribuce

**Swift Package Manager** pro kód, tenký skript pro sestavení `.app`.
`swift build` a `swift test` fungují standardně — to recenzent očekává.

Podepisování Developer ID, notarizace přes API klíč z App Store Connect
(profil v Klíčence se ukázal jako nespolehlivý). Vydání do veřejného
repozitáře, odkud si aplikace sama stahuje aktualizace.

CI na GitHubu: **překlad a testy při každém pushi, nic víc.**

### Kde se podepisuje — rozhodnuto

**Podpis, notarizace a vydání běží na vývojářském Macu, ne v CI.**

Technicky by to CI zvládlo: na macOS runnerech GitHubu jsou `xcrun notarytool`
i `stapler` předinstalované a certifikát se dá naimportovat z tajného klíče do
dočasné klíčenky. Ověřeno v dokumentaci, ne odhadnuto.

Důvod proti je jeden a váží víc než ušetřený příkaz. Vyžadovalo by to nahrát
do GitHub Secrets **soukromý podpisový klíč** (`.p12` i s heslem). Developer ID
je vázané na identitu autora u Applu: kdo ten klíč získá, podepisuje libovolný
kód jeho jménem a takový software projde Gatekeeperem na každém Macu. Při
zneužití Apple certifikát odvolá a dopadne to na všechno, co jím kdy bylo
podepsáno.

Runnery jsou sdílená infrastruktura a tajný klíč se na nich při běhu dešifruje
do prostředí. Z pull requestů z forků se tajné klíče nepředávají, ale
kompromitovaný účet nebo změna workflow to obejde.

U projektu, který stojí na tom, že si uživatel může ověřit, co se děje s jeho
hlasem a jeho klíčem, by poslání vlastní podpisové identity do cizí
infrastruktury bylo rozporné. Vydání nebudou častá a jeden lokální příkaz je
levnější než to riziko.

Soukromý klíč zůstává na stroji, v souboru mimo repozitář s právy `600`,
a zálohovaný — bez něj je certifikát u Applu nepoužitelný a musí se vydat nový.

## Web

Jedna stránka na GitHub Pages. Co má říct, v tomto pořadí:

1. **Voice input for the rest of us** — a pro koho to je
2. Důkaz té mezery (ta tři měření výše)
3. Jak to funguje — tři věty a obrázek panelu
4. Stažení
5. Otevřený kód: odkaz do zdrojáků na místo, kde se posílá zvuk

Grafika: ikona a snímky aplikace. Bez animací a bez marketingového balastu —
u ukázky práce působí střídmost lépe.

## Licence a příspěvky

**MIT.** Krátká, schválená OSI, a hlavně obsahuje zřeknutí se odpovědnosti —
to u aplikace, která odchytává klávesnici, nahrává mikrofon a vyměňuje si
vlastní binárku, není formalita.

Beerware byla zvážena a zamítnuta: není schválená OSI a zřeknutí se
odpovědnosti neobsahuje vůbec.

**Příspěvek dobrovolný, nikde nevynucovaný.** Jeden řádek na konci README
a tlačítko Sponsor v repozitáři — ne banner, ne výzva v aplikaci, ne prosba
při instalaci. Aplikace sama o peníze nikdy nežádá.

Technicky GitHub Sponsors (`.github/FUNDING.yml`), protože návštěvník
nepotřebuje zakládat účet jinde a v repozitáři se objeví tlačítko samo.

## Fáze 2 — texty a web ve více jazycích

Mimo v1. Až bude aplikace venku a ověřená:

- **Podtitulek ve více jazycích.** Česky zhruba *„Hlasový vstup pro méně
  rozšířené jazyky."* — znění k doladění, tohle je pracovní verze. Ostatní
  jazyky až od lidí, kteří jimi mluví: slogan je ze všech textů nejhůř
  přeložitelný a špatně přeložený působí hůř než ponechaný anglicky.
- Web v jazycích, které má aplikace lokalizované.
- Přepínač jazyka na webu, výchozí podle prohlížeče.

Platí tu stejná zásada jako u rozhraní: **aparát připravit úplně, dodat jen to,
za co lze ručit.** U projektu, který stojí na tom, že bere malé jazyky vážně,
by odbytý překlad do maďarštiny popřel vlastní sdělení.

## Rizika

**Obchodní otisk.** Dnešní repozitář jmenuje Journeyman, CFMOTO, Fakturoid,
Helios, Nextup, ISIR a ISDS. Ve výchozím slovníku ani v dokumentaci nového
projektu nebude nic z toho.

**Čísla z účtu.** Spotřeba a limit autora se do veřejných textů nedostanou.

**Aktualizátor stahuje a spouští kód.** To je místo, které bude čtena
nejpozorněji. Ověřování je po revizi poctivé a je to spíš příležitost než
riziko — ale komentáře v něm musí být srozumitelné.

**Míchání přepisu s novými funkcemi.** Při chybě po vydání nepůjde snadno
rozlišit, jestli pochází z přepisu nebo z nové funkce. Zadavatel to vzal na
vědomí.

## Chyby, které se nesmí zopakovat

Nálezy revize MyVoiceInput v2.4..v2.8. Nejsou to teoretické výhrady — každá
z nich byla buď vydaná uživatelům, nebo těsně před vydáním. Dvě první jsou
ověřené měřením na stroji, ne převzaté.

**`SMAppService.mainApp.status` vrací pro nikdy neregistrovanou aplikaci
`.notFound`, ne `.notRegistered`.** Ověřeno samostatným bundlem: `.notFound`
(raw 3). Podmínka „není neregistrovaná" je proto u čisté instalace vždy
splněná. Kód se nikdy nesmí ptát negativně — musí vyjmenovat stavy, které
znamenají, že registrace existuje: `.enabled` a `.requiresApproval`.

**Příznak „už jsem to udělal" se zapisuje až po úspěchu, nikdy před
pokusem.** V MyVoiceInput se nastavoval před `register()`, takže spuštění
z připojeného DMG první spuštění navždy spotřebovalo a aplikace se po
přihlášení nespustila nikdy.

**Heuristika „je to upgrade?" se smí opírat jen o předvolby, které zapisuje
uživatel.** `legacyKeyMigrated` zapisuje čtení klíče jako vedlejší efekt;
po smazání předvoleb a přeinstalaci (položka v Klíčence přežije) by skutečně
první spuštění vypadalo jako upgrade.

**`set -euo pipefail` + `git describe` v záložní větvi = build spadne.**
Ověřeno: v repozitáři bez tagů končí skript kódem 128 a na záložní hodnotu
se nikdy nedojde. Každé volání, jehož selhání je očekávané, potřebuje
`|| true`. Tohle je **druhý** případ téhož v jednom projektu — první byl
`grep -q` v rouře, kde SIGPIPE shodil celý příkaz.

**Automatické zastavení musí srovnat i stav, který hlídá.** Strop délky
nahrávky zastavoval nahrávání, ale nechával `rightCmdDown == true`. Další
stisk se pak vyhodnotil jako „žádná změna" a zahodil — uživatel domluví
celou větu do prázdna. A je to vidět jen v té poruše, kterou strop řeší.

**Přeplánování odpočtu musí odečíst, co už uběhlo.** Zkrácení stropu za
běhu nahrávku naopak prodloužilo.

**Menu se nesmí vyměňovat, když může být otevřené.** `statusItem.menu =
buildMenu()` z dokončení přepisu zavře menu uživateli pod kurzorem.
Obsah patří do `NSMenuDelegate.menuNeedsUpdate`, ne do přestavby po
události.

**Odložené úklidové bloky musí jít zrušit.** Obnova schránky naplánovaná
na +1,2 s po vložení přepíše cokoli, co uživatel mezitím do schránky dal —
třeba kliknutím na položku historie. Takový blok se musí držet jako
`DispatchWorkItem` a rušit.

## Co zůstane starému projektu

MyVoiceInput zůstane privátní a funkční, dokud NativeVoice nebude ověřený
v provozu. Issues #10 a #11 se zavřou až v novém projektu.

## Viditelnost repozitáře během vývoje

Repozitář je **soukromý, dokud není hotový**; zveřejní se až se vším všudy.
Jako ukázka práce působí lépe projekt, který od prvního pohledu funguje.

**Z toho plyne dvojí omezení, které se musí uhlídat:**

Dokud je repozitář soukromý, **odkazy z aplikace vracejí 404** komukoli
kromě vlastníka. V MyVoiceInput se přesně tohle stalo: odkaz „Report an
issue" v About panelu vedl na privátní repozitář a vyšel takhle ve dvou
vydáních, než si toho všimla revize. Odkazy se proto píšou rovnou na
cílové veřejné adresy a **ověří se v den zveřejnění**, ne dřív a ne „však
ono to bude sedět".

**Samoaktualizace přes vydání nefunguje, dokud je repozitář soukromý.**
Během vývoje se tedy nic nevydává — instaluje se lokálním buildem.
**První vydání je až to, které doprovází zveřejnění.** Žádné „zatím to
vydáme do privátního a pak přepneme".

Kontrolní seznam ke dni zveřejnění je proto součástí plánu, ne něco, co
se dodělá potom.

## Otevřené otázky

Žádné blokující. K rozhodnutí při implementaci:

*(žádné)*
