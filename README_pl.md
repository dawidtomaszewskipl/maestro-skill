# maestro

**maestro** zamienia agenta, z którym rozmawiasz, w dyrygenta zespołu modeli. Sam nie musi pisać
kodu: przeprowadza z Tobą krótki wywiad, pisze plan, daje go do krytyki modelom z **innych rodzin**,
przekazuje budowę modelowi, który najlepiej pasuje do zadania, sprawdza wynik, uruchamia testy,
commituje i raportuje, kto co zrobił i ile to kosztowało.

Działa w czterech agentach: **Claude Code**, **Codex**, **Cursor** (CLI `agent`) i **agy**
(Antigravity). Korzysta z modeli czterech rodzin: Claude, OpenAI (GPT), Google (Gemini) i xAI (Grok).

maestro wyrósł z route 3.4 i jest osobnym skillem. `/route` działa dalej bez zmian, oba można mieć
zainstalowane jednocześnie.

## Jak wygląda praca

```text
/maestro dodaj eksport listy faktur do CSV
```

1. **Wywiad.** Dyrygent dopytuje o to, czego nie da się wyczytać z kodu.
2. **Przydział.** Wybiera wykonawcę i krytyków i pokazuje to w jednej linii, np.
   `implementer=opus=claude-opus-5-5 (native) · critic=sol=gpt-6.1-sol (codex) · row 3`.
   Jednym słowem możesz to zmienić („niech robi sol”).
3. **Plan i krytyka.** Plan czytają modele z innej rodziny niż wykonawca, bo modele jednej rodziny
   mają te same ślepe plamy. Poprawki trwają do akceptacji albo do limitu rund.
4. **Budowa.** Wykonawca pracuje według planu.
5. **Kontrola.** Dyrygent czyta diff i uruchamia testy. Na życzenie dochodzi review modelu z innej
   rodziny.
6. **Poprawki** (maksymalnie 3 rundy), **commit** i **raport**: kto, czym, ile tokenów.

Przerwa w połowie (limit, zamknięty laptop) nie przepada: `/maestro --resume` kontynuuje od miejsca,
w którym run stanął.

## Co nowego względem route

Przebieg pracy, flagi i rubryka wyboru wykonawcy są takie same jak w route 3.4. Zmienia się to,
**gdzie** uruchamiasz, **kim** dysponujesz i **co się dzieje, gdy coś się skończy albo przerwie**.

| | route 3.4 | maestro |
| --- | --- | --- |
| Gdzie działa | tylko Claude Code | Claude Code, Codex, Cursor, agy; sam wykrywa, w którym jest |
| Rodziny modeli | Claude, OpenAI, Google | + **xAI (Grok)** przez Cursora |
| Nowy model (np. nowy Opus albo Sol) | trzeba edytować skill | **sam go znajdzie** na listach modeli i sprawdzi, czy masz do niego dostęp |
| Skończył się limit Claude w Claude Code | run staje | ten sam model Claude przez **agy**, potem przez **Cursora** |
| Dwa runy w jednym repozytorium | mogły na siebie wpaść | drugi zostaje odrzucony (blokada repozytorium) |
| Zamknięcie sesji w trakcie budowy | budowa jest związana z sesją Claude Code | budowa działa dalej, `--resume` ją przejmuje (poza interaktywnym Claude Code) |
| Linia przydziału | nazwa slotu (`critic=astra`) | dokładny model i droga (`astra=gpt-6-astra (codex)`) |
| Katalog stanu i polityka | `.route/`, `route.policy.yml` | `.maestro/`, `maestro.policy.yml` |

### Co to oznacza w praktyce

- **Uruchamiasz tam, gdzie akurat pracujesz.** Dyrygentem jest model danego agenta. W Codex
  kieruje np. Sol, więc krytyków maestro dobiera z Claude, Gemini albo Groka. Reguła „krytyk spoza
  rodziny wykonawcy” dostosowuje się sama.
- **Więcej niezależnych spojrzeń.** Przy zmianach wysokiego ryzyka (uprawnienia, pieniądze,
  współbieżność, integralność danych, migracje zmieniające dane) drugi krytyk pochodzi z trzeciej
  rodziny. Z Grokiem częściej są dostępne trzy rodziny.
- **Grok jest na razie oznaczany jako tymczasowy** (`provisional`). Jako krytyk znajdował prawdziwe
  błędy, ale jako wykonawca nie był jeszcze mierzony.
- **Część wykonawców tylko edytuje pliki, a testy uruchamia dyrygent.** Dotyczy Claude przez agy
  i przez `claude -p` oraz Gemini. Cursor uruchamia testy tylko wtedy, gdy jego piaskownica
  przeszła sprawdzenie dostępu. Dla Ciebie to trochę więcej kroków dyrygenta i mniej niespodzianek.
- **Testy są nietykalne.** Zatrzymanie zadania nigdy nie zabija testów. Jeśli maestro nie jest
  pewien, który proces jest testem, staje (`blocked`) zamiast strzelać na ślepo.

## Porównanie hostów

| | Claude Code | Codex | Cursor (`agent`) | agy |
| --- | --- | --- | --- | --- |
| Wywołanie | `/maestro` | `$maestro` | `/maestro` | `/maestro` |
| Co trzeba ustawić | nic | uruchomić Codex z `--sandbox danger-full-access` (dyrygent musi sięgać do API modeli i uruchamiać testy) | plik `.cursor/cli.json` w projekcie z listą dozwolonych komend ([wzór](docs/hosts.md#adapters)); **nigdy `--force`**, bo wyłącza piaskownicę | tylko sesja interaktywna; zatwierdzasz komendy i zapisy plików albo dodajesz reguły `permissions.allow` |
| Czy dyrygent może sam budować (`self`) | tak | tak | **nie**: Cursor nie zdradza, jakim modelem jest dyrygent, więc buduje zawsze inny model | **nie**, z tego samego powodu |
| Jak uruchamia modele Claude | subagenty Claude Code | `claude -p` | `claude -p` | `claude -p` |
| Jak czeka na długie zadania | powiadomienie Claude Code, jak w route | własne zadania maestro, sprawdzane co 25 s | jak Codex | jak Codex, co 8 s |
| Jak pyta Ciebie | okno z opcjami | okno, jeśli Codex je udostępnia, inaczej zwykłe pytanie | zwykłe pytanie, potem czeka na odpowiedź | okno pytania agy |
| Budowa przeżywa zamknięcie sesji | jak w route | tak (zmierzone ponad 10 min) | tak | tak |
| Praca bez nadzoru (`--unattended`) | `claude -p "/maestro --unattended …"` | `codex exec` | `agent -p` | **nie** (w trybie `-p` agy odmawia wszystkich komend) |
| Zrzuty ekranu przy zmianach UI | tak | tak | tak (potrzebne `Shell(npx)`) | tak |
| Sprawdzone od początku do końca | tak | tak, również równoległy podział pracy | tak | tak |

**Który host wybrać?** Najwygodniejszy jest interaktywny Claude Code: wygodne pytania,
powiadomienia o końcu zadań, a dyrygent może sam zrobić małą zmianę. Codex przydaje się, gdy
skończył się limit Claude. Cursor i agy działają, ale wymagają konfiguracji uprawnień i nie pozwalają
dyrygentowi budować samodzielnie.

## Modele

| Rodzina | Sloty | Droga do modelu (po kolei) |
| --- | --- | --- |
| Claude | `opus`, `fable`, `sonnet`, `haiku` | natywnie (subagent albo `claude -p`) → agy → Cursor → api (`haiku`: natywnie → api, `fable` bez agy; api tylko z `--sdk` albo polityką `api.fallback`) |
| OpenAI | `astra` (najmocniejszy), `sol` (koń roboczy), `luna` (szybki, tani), `terra` (tylko na wyraźne życzenie) | `codex exec` |
| Google | `gemini` (Flash) | agy |
| xAI | `grok` (tymczasowy) | Cursor `agent -p` |

Slot oznacza **linię modeli**, a nie konkretny model: `sol` to najnowszy `gpt-*-sol`, jaki ma Twoje
konto. Na starcie runu maestro czyta listy modeli z CLI, wybiera najnowszy i sprawdza go jednym
tanim wywołaniem. Wynik pamięta przez 7 dni. Wybrany model obowiązuje do końca runu.

Chcesz konkretną wersję albo drogę? `--model=opus@agy` wymusza drogę, a `pin` w polityce przypina
wersję.

## Koszty i czas

- **Pierwszy run na danym hoście** kosztuje kilka tanich wywołań sprawdzających modele. Kolejne
  runy przez 7 dni ich nie powtarzają.
- **Więcej krytyków** oznacza więcej tokenów w fazie planu. Gemini i Grok zużywają jednak inne pule
  niż Claude i OpenAI. Przy budowie samego maestro wyszło po ok. 0,4 mln tokenów wejścia na każdy
  z nich.
- **Poza Claude Code** dyrygent odpytuje zadania w pętli. To kilka dodatkowych wywołań narzędzi,
  bez kosztu modelu.
- Każde wywołanie modelu trafia do `.maestro/ledger.jsonl` (model zamówiony i ten, który faktycznie
  odpowiedział, tokeny, czas), a raport je podsumowuje.

## Instalacja

```bash
cd maestro-skill
./install.sh                      # dla Ciebie: Claude Code, Codex, Cursor i agy
./install.sh ~/code/moj-projekt   # tylko dla jednego projektu
./install.sh --check              # gdzie jest zainstalowany
./install.sh --check=live         # każdy host pokazuje, czy widzi skill (kilka tanich wywołań)
```

Wymagania: Linux, bash ≥ 5, jq ≥ 1.6, git, util-linux (`setsid`, `flock`) oraz te z `claude`,
`codex`, `agent`, `agy`, których chcesz używać, zalogowane. Instalator nie rusza `/route`.
**Nie uruchamiaj `/route` i `/maestro` jednocześnie w tym samym repozytorium**: route nie widzi
blokady maestro.

### Kredyt API (`--sdk`)

Plan Max daje co miesiąc kredyt API: $200 na Max 20x, $100 na Max 5x. Kredyt przepada z końcem
okresu rozliczeniowego. Obejmuje Claude API i Claude Agent SDK, **ale nie Claude Code**. maestro
może puszczać na nim Claude-workery, gdy skończy się limit 5-godzinny albo tygodniowy subskrypcji:

1. claude.ai → Settings → Billing: podłącz organizację Console. To jednorazowe, kredyt pojawia
   się dopiero potem. Nowa subskrypcja czeka 7 dni.
2. W tej organizacji Console utwórz workspace i klucz API **w nim** (klucz na poziomie organizacji jest odrzucany: „not scoped to a workspace”). Ustaw limit wydatków workspace'u jako twardy
   bezpiecznik.
3. We własnym terminalu: `mkdir -p ~/.config/maestro && install -m 600 /dev/stdin ~/.config/maestro/anthropic-api-key`, wklej klucz, potem Ctrl-D.
4. `./install.sh --sdk` (Node ≥ 18) instaluje przypiętą wersję Agent SDK obok skilla.
5. `~/.agents/skills/maestro/bin/maestro-sdk --check` powinno zwrócić `"available": true`.

Potem `/maestro --sdk <zadanie>` puszcza wszystkie Claude-workery przez SDK na tym kluczu. Z
`api: {fallback: true}` w `~/.config/maestro/policy.yml` maestro przełącza się na nie samo, gdy
limit skończy się w trakcie przebiegu. `api.max_usd_per_run` (domyślnie $20) ogranicza jeden
przebieg. Raport pokazuje, ile przebieg wydał.

Gdy limit się skończy, staje też Twoja sesja Claude Code. Dyryguj wtedy z Codexa, Cursora albo
agy, a z kredytu niech korzystają tylko Claude-workery. Claude Code uruchomiony na kluczu API to
użycie Claude Code i nie pobiera kredytu.

## Przykłady

```text
/maestro dodaj eksport listy faktur do CSV
/maestro --setup <zadanie>                   # skonfiguruj run pytaniami
/maestro --plan-only <zadanie>               # sam plan z krytyką, bez budowy
/maestro --model=grok --critic=sol,opus <zadanie>
/maestro --model=opus@agy popraw paginację   # Opus przez agy
/maestro --review=cross <zadanie>            # review modelu z innej rodziny
/maestro --resume                            # dokończ przerwany run
```

Flagi: `--model=<slot>[@droga]`, `--critic=…`, `--reviewer=…`, `--review[=full|self|cross]`,
`--rounds=n`, `--tests=covering|full[,browser]`, `--skip-tests`, `--cascade[=luna|haiku|gemini]`,
`--setup`, `--plan-only`, `--resume`, `--unattended`, `--host=…`. Zwykłe słowa też działają:
„krytykuj grokiem”, „opus przez agy”, „bez testów przeglądarkowych”.

## Polityka

Stałe preferencje zapisujesz w `maestro.policy.yml` w repozytorium albo w
`~/.config/maestro/policy.yml` dla siebie. Możesz:

- wykluczyć slot (`deny: [fable]`) albo drogę (`transports: {deny: [opus@cursor]}`);
- przypiąć wersję (`pin: {sol: "6.1"}`);
- wyłączyć całą rodzinę (`families: {google: off}`);
- ustawić wysiłek modelu dla etapów.

[Przykład z komentarzami](docs/examples/maestro.policy.yml).

## Znane ograniczenia

- **Grok** jako wykonawca nie był jeszcze mierzony.
- **Claude przez Cursora** nie był sprawdzony, bo na tym koncie limit Cursora na Claude jest
  wyczerpany.
- **Przejście na inną drogę po wyczerpaniu limitu** w interaktywnym Claude Code idzie przez
  subagenty i tej ścieżki nie da się zasymulować. Sprawdzone było z dyrygentem `claude -p`.
- **Proces, który odłączy się w pierwszej sekundzie** od zadania, może zostać niezauważony.
  maestro zgłasza wtedy podejrzane procesy i nie zabija niczego, czego nie umie przypisać.
- **Kredyt API** widać tylko w Console. `cost_usd` w ledgerze to szacunek SDK. To, czy wywołanie
  zeszło z kredytu, czy z przedpłaconego salda, sprawdzono dotąd tylko ręcznie.

Przypadki, które warto sprawdzić ręcznie, są opisane krok po kroku w
[docs/manual-checks_pl.md](docs/manual-checks_pl.md).

## Dokumentacja techniczna

Pliki w `docs/` czyta dyrygent w trakcie pracy, dlatego są precyzyjne, a nie przystępne:
[hosty](docs/hosts.md) · [katalog modeli](docs/catalog.md) · [komendy](docs/commands.md) ·
[workerzy](docs/workers.md) · [polityka](docs/policy.md) · [setup](docs/setup.md) ·
[cascade](docs/cascade.md) · [checkpoint](docs/checkpoint.md) · [ledger](docs/ledger.md) ·
[praca bez nadzoru](docs/unattended.md) · [piaskownica](docs/sandbox-and-preflight.md) ·
[rozwiązywanie problemów](docs/troubleshooting.md) ·
[pomiary wydania 1.0.0](docs/release-1.0.0.md)

English: [README.md](README.md).
