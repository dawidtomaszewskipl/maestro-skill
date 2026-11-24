# maestro

**maestro** to dodatek do asystentów programistycznych AI. Wpisujesz jedno polecenie, a asystent,
z którym właśnie rozmawiasz, przestaje być samotnym programistą i zostaje **dyrygentem** małego
zespołu modeli AI z różnych firm: dopytuje Cię o to, czego nie wie, pisze plan, daje ten plan do
sprawdzenia modelom z innych firm, przekazuje kodowanie modelowi, który najlepiej pasuje do
zadania, sprawdza wynik, uruchamia Twoje testy, commituje i mówi, kto co zrobił i ile to
kosztowało.

Działa wewnątrz **Claude Code** — interaktywnie albo bez okna, przez `claude -p`. Korzysta
z modeli trzech **rodzin**: Claude (Anthropic), GPT (OpenAI, przez CLI `codex`) i Gemini (Google,
przez `agy`, Antigravity).

Usunięte w 2.0.0: dyrygowanie z Codexa, Cursora albo agy (`$maestro`, `--host`), worker Cursora (`agent`) i slot Grok (rodzina xAI) — Codex i agy zostają jako workerzy.

English: [README.md](README.md). Przewodnik dla tych, którzy chcą zobaczyć całość (po angielsku):
[docs/guide/](docs/README.md).

## Po co zespół i dlaczego z różnych firm

Każdy model ma ślepe plamy, a modele jednej firmy zwykle mają te same. Plan napisany przez Claude
i sprawdzony tylko przez innego Claude przeoczy to samo dwa razy. Dlatego maestro ma jedną
żelazną regułę: **kto sprawdza, nigdy nie pochodzi z tej samej rodziny co ten, kto pisał.** Claude
pisze kod, GPT sprawdza plan; GPT pisze, sprawdza Claude albo Gemini. Przy ryzykownych zmianach
(uprawnienia, pieniądze, współbieżność, migracje danych) dochodzi drugi krytyk z trzeciej rodziny.

Dyrygent nie musi sam pisać kodu. Wybiera wykonawcę według krótkiej spisanej rubryki: trudny
problem poprawności idzie do najmocniejszego modelu, zwykła funkcja do modelu uniwersalnego,
mechaniczny szkielet do taniego i szybkiego — i mówi, którą regułę zastosował. Jedno słowo od
Ciebie zmienia wybór.

## Jak wygląda przebieg

```text
/maestro dodaj eksport listy faktur do CSV
```

1. **Wywiad.** Dyrygent pyta o to, czego nie da się wyczytać z kodu. Jedno pytanie naraz, aż nie
   zostanie żadna luka.
2. **Przydział.** Wybiera wykonawcę i krytyków i pokazuje ich w jednej linii, z powodem każdego
   wyboru i dokładnym modelem za każdą nazwą. „Niech buduje sol” to zmienia.
3. **Plan i krytyka.** Pisze plan. Krytycy z innych rodzin czytają plan (jeszcze nie kod)
   i odpowiadają: zatwierdzam albo popraw. Plan krąży, aż każdy krytyk go zatwierdzi, do limitu
   rund (dwie, chyba że ustawisz inaczej). Nie zatwierdzony na limicie? Model z
   trzeciej rodziny rozstrzyga raz to, co zostało (nigdy przy ryzykownej zmianie); jeśli któraś
   uwaga się utrzyma, przebieg staje i oddaje Ci spór do rozstrzygnięcia.
4. **Budowa.** Wybrany model pisze kod w granicach, które wyznaczył plan.
5. **Kontrola.** Dyrygent sam czyta cały diff i uruchamia testy. Na życzenie model z innej
   rodziny niż wykonawca — zwykle ten, który krytykował plan — recenzuje wynik względem planu.
6. **Poprawki, commit, raport.** Uwagi i czerwone testy wracają do wykonawcy (najwyżej trzy
   rundy). Potem dyrygent commituje i raportuje: kto co zrobił, jakim modelem, ile tokenów, co
   pominięto.

Przerwa — wyczerpany limit, zamknięty laptop, zakończona sesja? Nic nie przepada:
`/maestro --resume` kontynuuje od miejsca, w którym przebieg stanął, także w nowej sesji Claude
Code.

## Szybki start

Potrzebujesz Linuksa, bash ≥ 5, jq ≥ 1.6, gita i util-linux (`setsid`, `flock`), Claude Code
(`claude`) oraz tych CLI workerów, których chcesz w zespole — zainstalowanych i zalogowanych
(`codex`, `agy`). maestro korzysta z Twoich subskrypcji; nie dodaje żadnego własnego konta.

```bash
git clone <to repozytorium> maestro-skill && cd maestro-skill
./install.sh                    # kopiuje skill do ~/.claude/skills/maestro
./install.sh --check            # pokazuje, gdzie jest zainstalowany
```

Potem, w projekcie z czystym drzewem gita:

```text
/maestro dodaj eksport listy faktur do CSV                          # w Claude Code
claude -p "/maestro --unattended dodaj eksport listy faktur do CSV"     # bez okna
```

Aktualizacja z 1.x: instalator zamienia stary symlink `~/.claude/skills/maestro` na kopię i wymienia
pozostałości (`~/.agents/skills/maestro`, `~/.gemini/config/skills/maestro`), które możesz usunąć.

Pierwszy przebieg w repozytorium zużywa kilka tanich wywołań na sprawdzenie, do których modeli
sięgają Twoje konta; kolejne przebiegi w tym repozytorium korzystają z tej odpowiedzi do siedmiu
dni, o ile wersja CLI i konto się nie zmieniły. Szczegóły: [setup and running](docs/guide/setup-and-hosts.md).

## Polecenia, których naprawdę będziesz używać

| Polecenie | Co robi |
| --- | --- |
| `/maestro <zadanie>` | pełny przebieg opisany wyżej |
| `/maestro --setup <zadanie>` | konfiguracja przebiegu przez kilka pytań zamiast flag; kończy się linią flag do ponownego użycia |
| `/maestro --plan-only <zadanie>` | tylko wywiad, plan i krytyka — bez kodu i bez commita |
| `/maestro --model=sol <zadanie>` | wybór wykonawcy (nazwa slotu z tabeli poniżej; `opus@agy` wymusza też drogę do niego) |
| `/maestro --critic=astra,hydrogen <zadanie>` | wybór krytyków |
| `/maestro --review=cross <zadanie>` | dodatkowa recenzja gotowego kodu przez model z innej rodziny niż wykonawca, domyślnie przez krytyka planu (`full` dołącza własne czytanie dyrygenta; `self` to tylko czytanie dyrygenta, bez recenzenta) |
| `/maestro --unattended <zadanie>` | nikogo nie ma przy klawiaturze: drobne luki stają się zapisanymi założeniami, prawdziwe decyzje czysto zatrzymują przebieg |
| `/maestro --sdk <zadanie>` | Claude-workerzy pracują na kredycie API planu Max zamiast na subskrypcji (patrz [Kredyt API](#kredyt-api)) |
| `/maestro --advisor <zadanie>` | opcjonalne, domyślnie wyłączone: wykonawca może raz się zatrzymać (`--advisor-checkpoints=2` albo `3`, jeśli więcej) i zapytać model z innej rodziny, tylko do odczytu, o krótką radę, którą dyrygent mu przekazuje; `--advisor=astra` wskazuje go z nazwy. Rada nigdy nie jest bramką i nie jest jeszcze zmierzona |
| `/maestro --resume` | dokończenie przerwanego przebiegu |

Zwykłe słowa też działają: „krytykuj argonem”, „opus przez agy”, „bez testów przeglądarkowych”.
Wszystkie flagi są wymienione w `SKILL.md`; ściąga z objaśnieniami jest w
[słowniku](docs/guide/glossary.md).

## Jakich modeli może używać

Nazwa taka jak `sol` czy `opus` to **slot**: *linia* modeli, nie konkretna wersja. Na starcie
przebiegu maestro czyta listy modeli Twoich CLI, wybiera najnowszy model każdej linii, do którego
Twoje konto ma dostęp, sprawdza go jednym tanim wywołaniem i trzyma się dokładnie tego modelu do
końca przebiegu. Nowy Opus albo nowy Sol nie wymaga aktualizacji maestro.

| Rodzina | Sloty | Do czego |
| --- | --- | --- |
| Claude | `opus` | codzienne funkcje, zmiany wieloetapowe, wszystko ze zrzutami ekranu i UI |
| | `fable` | najtrudniejsze problemy poprawności i duże przebudowy — najmocniejszy i najdroższy (Fable 5.2) |
| | `sonnet` | mechaniczna budowa według ustalonego planu |
| | `haiku` | masowe edycje bez żadnej oceny |
| OpenAI | `astra` | najmocniejszy krytyk ryzykownych planów; wykonawca, gdy ogranicza Cię budżet Claude |
| | `sol` | koń roboczy: duże samodzielne kawałki pracy i domyślny krytyk budowy robionej przez Claude |
| | `luna` | szybki i tani: szkicuje w kaskadzie (niżej) |
| | `terra` | starsza linia, używana tylko gdy ją wskażesz |
| Google | `argon` | krytyk i recenzent od Google; buduje tylko gdy go wskażesz |
| | `carbon`, `neon` | Gemini 4 Carbon i Neon — tu jeszcze niezmierzone: używane tylko gdy wskażesz je jako wykonawcę, krytyka albo recenzenta (nigdy jako szkicującego w kaskadzie, nigdy wybierane na arbitra) |
| | `hydrogen` | szybka i tania praca mechaniczna, gdy chcesz oszczędzić pulę Claude — Gemini 4 Hydrogen (następca Gemini 3.8 Flash według zapowiedzi Google z 2026-11-12; Flash nie jest już używany) |

Do slotu może prowadzić więcej niż jedna droga (**transport**): `opus` działa natywnie w Claude
Code, albo przez agy, albo na kredycie API (`fable` i `haiku`: natywnie albo na kredycie API). Gdy jedna droga wyczerpie limit
w trakcie przebiegu, maestro kontynuuje ten sam model następną drogą i mówi o tym.

Dwa tańsze tryby: `--cascade` pozwala tańszemu modelowi najpierw naszkicować zmianę, a bramka
decyduje, czy szkic wystarczy, czy musi wejść mocniejszy model; `--plan-only` daje Ci
zrecenzowany plan za cenę samej krytyki.

## Ile to kosztuje

- Każde wywołanie modelu schodzi z subskrypcji tego CLI, które je obsłużyło: GPT z ChatGPT, Gemini
  z agy; Claude z Twojego planu Claude, gdy działa natywnie, z puli agy, gdy idzie przez agy,
  a na drodze `api` z kredytu API. Więcej krytyków to więcej tokenów
  na etapie planu, ale rozłożonych na pule, które inaczej stałyby bezczynnie.
- Każde wywołanie trafia do **ledgera** (`.maestro/ledger.jsonl`): model zamówiony, model, który
  odpowiedział, tokeny i czas. Raport sumuje to per etap i per rodzina. Tokeny nigdy nie są
  pokazywane jako pieniądze — poza wywołaniami na kredycie API, które mają szacunek w dolarach.
- Wyczerpany limit to rutyna, nie awaria: slot Claude przechodzi na następną drogę; w innym
  wypadku przebieg zapisuje checkpoint i staje, a `--resume` kontynuuje po odnowieniu limitu.

### Kredyt API

Plan Max daje co miesiąc kredyt API: $200 na Max 20x, $100 na Max 5x. Kredyt przepada z końcem
okresu rozliczeniowego. Obejmuje Claude API i Claude Agent SDK, **ale nie Claude Code**. maestro
może puszczać na nim Claude-workerów, gdy skończy się limit 5-godzinny albo tygodniowy
subskrypcji:

1. claude.ai → Settings → Billing: podłącz organizację Console. To jednorazowe, kredyt pojawia
   się dopiero potem. Nowa subskrypcja czeka 7 dni.
2. W tej organizacji Console utwórz workspace i klucz API **w nim** (klucz na poziomie organizacji
   jest odrzucany: „not scoped to a workspace”). Ustaw limit wydatków workspace'u jako twardy
   bezpiecznik.
3. We własnym terminalu: `mkdir -p ~/.config/maestro && install -m 600 /dev/stdin
   ~/.config/maestro/anthropic-api-key`, wklej klucz, potem Ctrl-D.
4. `./install.sh --sdk` (Node ≥ 18) instaluje przypiętą wersję Agent SDK obok skilla.
5. `~/.claude/skills/maestro/bin/maestro-sdk --check` powinno zwrócić `"available": true`.

Potem `/maestro --sdk <zadanie>` puszcza wszystkich Claude-workerów przez SDK na tym kluczu.
Z `api.fallback = true` w `~/.config/maestro/policy.toml` maestro przełącza się na niego samo,
gdy limit skończy się w trakcie przebiegu. `api.max_usd_per_run` (domyślnie $20) ogranicza jeden
przebieg. Raport pokazuje, ile przebieg wydał.

Gdy limit się skończy, staje też Twoja sesja Claude Code; `--sdk` od początku zostawia subskrypcję
wyłącznie dyrygentowi. Claude Code uruchomiony na kluczu API to użycie Claude Code i nie pobiera
kredytu.

## Stałe preferencje

Zapisujesz je w `maestro.policy.toml` w repozytorium (dla zespołu) albo w
`~/.config/maestro/policy.toml` (dla siebie): nigdy nie wybieraj slotu (`deny = ["fable"]`), nigdy nie
używaj drogi (`transports.deny = ["opus@agy"]`), przypnij wersję (`pin.sol = "6.1"`), wyłącz
rodzinę (`families.google = "off"`), ustaw wysiłek modelu per etap. Flagi biją plik repozytorium,
a ten bije Twój własny. [Przykład z komentarzami](docs/examples/maestro.policy.toml).

## Bezpieczne domyślne zachowania

Workerzy nie dotykają Twoich ustawień, hooków ani pluginów: każdy zewnętrzny worker startuje
z oczyszczonym środowiskiem, w piaskownicy swojego CLI albo ze stałym zestawem narzędzi. Jeden
przebieg na repozytorium naraz (drugi jest odrzucany). Workerzy, których nie da się zamknąć
w piaskownicy, tylko edytują pliki, a testy uruchamia dyrygent. Testów nikt nigdy nie zabija,
nawet gdy worker się zawiesi. Cały stan przebiegu leży w `.maestro/` i jest zapisywany wyłącznie
przez audytowane skrypty pomocnicze. Nic nie jest commitowane, zanim dyrygent sam nie przeczyta
diffu i nie uruchomi testów.

## Znane ograniczenia

- **Argon** jako wykonawca nie był jeszcze mierzony, a **Gemini 4 Hydrogen** jest nowy: Google go
  nie ogłosił, a ledger nie ma jeszcze żadnych jego przebiegów.
- **Fable i Haiku** nie mają drugiej drogi w subskrypcji: gdy skończy się ich limit natywny, dalej
  pracują tylko na kredycie API (`--sdk` albo `api.fallback = true`).
- **Kredyt API** widać tylko w Console; kwota w dolarach w ledgerze to szacunek SDK, nie faktura.

Przypadki, które warto sprawdzić ręcznie, są opisane krok po kroku w
[docs/manual-checks_pl.md](docs/manual-checks_pl.md).

## Testy

`bash tests/run.sh` uruchamia zestaw testów (bez wywołań modeli; około trzech minut; grupa lint
wymaga `shellcheck`). Obejmuje skrypty pomocnicze w `bin/`, nie dokumentację.

## Co czytać dalej

- [docs/README.md](docs/README.md) — mapa wszystkich stron.
- Przewodnik (po angielsku): [how it works](docs/guide/how-it-works.md) · [models and
  roles](docs/guide/models-and-roles.md) · [costs and limits](docs/guide/costs-and-limits.md) ·
  [setup and running](docs/guide/setup-and-hosts.md) · [glossary](docs/guide/glossary.md).
- Strony techniczne w `docs/` czyta sam dyrygent w trakcie pracy, dlatego są precyzyjne, a nie
  przystępne: [hosty](docs/hosts.md) · [katalog modeli](docs/catalog.md) ·
  [komendy](docs/commands.md) · [workerzy](docs/workers.md) · [polityka](docs/policy.md) ·
  [setup](docs/setup.md) · [cascade](docs/cascade.md) · [checkpoint](docs/checkpoint.md) ·
  [ledger](docs/ledger.md) · [praca bez nadzoru](docs/unattended.md) ·
  [piaskownica](docs/sandbox-and-preflight.md) ·
  [rozwiązywanie problemów](docs/troubleshooting.md).
