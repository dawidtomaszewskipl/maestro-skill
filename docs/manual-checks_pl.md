# Ręczne sprawdzenia maestro

> **Do czego służy ta strona.** Lista sprawdzeń, których nie da się zautomatyzować — wymagają sesji interaktywnej, prawdziwego limitu albo oceny człowieka. Opis maestro po polsku: [README_pl.md](../README_pl.md); mapa dokumentacji: [docs/README.md](README.md).

Automatyczne testy i pomiary (ostatnio 14.11.2026, maestro 2.0.0: tylko Claude Code jako
dyrygent, workerzy przez Claude Code, Codex i agy) pokryły większość przypadków, ale kilku rzeczy
nie dało się sprawdzić bez Ciebie. Część wymaga sesji interaktywnej, część limitów, których nie da się
zasymulować, a część to po prostu ocena, jak się z tym pracuje. Poniżej każdy przypadek krok po
kroku.

**Co mi odesłać:** numer przypadku, co zauważyłeś i ścieżkę repozytorium. Ledger, checkpoint
i logi zadań z `.maestro/` przeczytam sam, bo pracujemy na tej samej maszynie. Gdy przypadek prosi
o fragment ekranu (np. linię przydziału), wklej go.

## Przygotowanie

Każdy przypadek najlepiej robić na osobnym, małym repozytorium testowym:

```bash
export MAESTRO_CANARY_ROOT=~/maestro-checks
~/dev/packages/maestro-skill/tests/canary/mkcanary.sh k1      # tworzy ~/maestro-checks/k1
cd ~/maestro-checks/k1
```

To mała biblioteka w bashu (`lib/str.sh`) z testem `bash tests/test_str.sh`, z jednym commitem
i z maestro zainstalowanym w projekcie.

**Zadanie testowe** (wklejasz jako `<zadanie>`):

> dodaj funkcję slugify do lib/str.sh: zamień tekst na małe litery, spacje i podkreślenia na
> myślniki, usuń wszystkie inne znaki, które nie są literą, cyfrą ani myślnikiem; z testami
> w tests/test_str.sh

Zwykle prowokuje prawdziwą uwagę krytyka o ustawieniach locale, więc widać, czy krytyka działa.

## Kolejność

Najwięcej powiedzą przypadki 1, 3 i 6. Przypadki 2 i 5 zrób przy okazji, gdy nadarzy się
sytuacja.

---

### 1. Claude przez agy (wymuszona droga)

**Cel:** sprawdzić, że model Claude uruchomiony przez agy buduje poprawnie. To ta sama droga, na
którą maestro przechodzi, gdy skończy się limit w Claude Code.

**Gdzie:** interaktywny Claude Code w `~/maestro-checks/k1`.

**Kroki:**
```text
/maestro --model=sonnet@agy --critic=sol --rounds=1 <zadanie>
```

**Oczekuję:**
- linia przydziału zawiera `sonnet=claude-sonnet-… (agy)`;
- wykonawca tylko edytuje pliki, a testy uruchamia dyrygent;
- na końcu jest commit i raport z wierszem, w którym `transport` to `agy`.

**Odeślij:** linię przydziału i swoje wrażenia (czas, czy coś się zacięło).

### 2. Przejście na inną drogę po wyczerpaniu limitu Claude (przy okazji)

**Cel:** to jedyna ścieżka przełączenia, której nie dało się zasymulować: interaktywny Claude
Code, w którym subagent dostaje komunikat o limicie.

**Kiedy:** podczas prawdziwego runu `/maestro`, w którym budowę robi `opus` albo `sonnet`
natywnie, a limit Claude Code się kończy.

**Oczekuję:**
- maestro mówi o przełączeniu drogi (`native → agy`) dla **tego samego** modelu, np.
  `claude-opus-5-5`;
- poprzednia próba zostaje sprzątnięta (protokół brudnego wyjścia), a budowa idzie dalej przez agy;
- w ledgerze są dwa wiersze tej samej roli: `native`, a potem `agy`.

**Odeślij:** komunikat o przełączeniu i ścieżkę repozytorium. Jeśli zamiast tego run stanął
z pytaniem, to też jest wynik.

### 3. Gemini 4 Hydrogen jako wykonawca

**Cel:** Hydrogen (slot `gemini` od 2.0.0) przeszedł tylko próbę „OK”. Trzeba sprawdzić, czy umie
zbudować zmianę jako worker, który tylko edytuje pliki (testy uruchamia dyrygent).

**Gdzie:** interaktywny Claude Code w nowym repozytorium testowym.

**Kroki:**
```text
/maestro --model=gemini --critic=sol --rounds=1 --review=cross <zadanie>
```

**Oczekuję:**
- przy wykonawcy pojawia się `gemini=gemini-4-hydrogen-… (agy)`;
- worker tylko edytuje pliki, testy uruchamia dyrygent;
- recenzja z innej rodziny niż Google, commit i raport.

**Odeślij:** linię przydziału, liczbę rund poprawek i wynik testów.

### 4. Dwa runy w jednym repozytorium

**Cel:** sprawdzić, że blokada repozytorium działa między dwiema sesjami Claude Code.

**Kroki:** w jednym terminalu uruchom `/maestro <zadanie>` w Claude Code. Gdy zacznie pracować,
w drugim terminalu w tym samym repozytorium uruchom drugi Claude Code i w nim `/maestro <zadanie>`.

**Oczekuję:** drugi run odmawia startu i mówi, kto trzyma blokadę (identyfikator runu, sesja).
Pierwszy pracuje dalej bez zakłóceń.

**Odeślij:** komunikat odmowy.

### 5. Nowy model (przy okazji)

**Cel:** sprawdzić najważniejszą obietnicę: nowy model bez edycji skilla.

**Kiedy:** po premierze nowego modelu (np. nowy Sol, Opus, Fable albo Gemini).

**Oczekuję:** w najbliższym runie linia przydziału pokazuje nową wersję. Jeśli Twoje konto nie ma
do niej dostępu, zobaczysz dopisek w rodzaju `(gpt-6.2-sol listed, denied for this account)`
i użytą starszą wersję.

**Odeślij:** linię przydziału.

### 6. Pierwszy run w prawdziwym projekcie

**Cel:** to najważniejsza ocena: czy plan i krytyka są użyteczne przy prawdziwej pracy, a nie na
zabawkowym repozytorium.

**Gdzie:** wybrany projekt (np. anvil-ui albo legat), interaktywny Claude Code.

**Kroki:**
```text
/maestro --plan-only <prawdziwe zadanie, które i tak miałeś zrobić>
```

**Oczekuję:** plan, uwagi krytyków z dwóch rodzin i lista decyzji dla Ciebie. Nic nie jest
budowane ani commitowane.

**Odeślij:** czy uwagi krytyków były trafne, czy coś było szumem, ile to trwało. Na tej podstawie
dostroję domyślnych krytyków i liczbę rund.

### 7. Claude-workery na kredycie API (`--sdk`, płatne: centy)

**Cel:** potwierdzić, że wywołania przez Agent SDK zdejmują **kredyt** z planu Max, a nie
przedpłacone saldo. W dokumentacji nie ma na to dowodu, widać to tylko w Console.

**Gdzie:** repozytorium z `tests/canary/mkcanary.sh`, dyrygent w Claude Code.

**Przed:** README.md → „API credit” (po polsku: README_pl.md → „Kredyt API”), kroki 1–5. Zanotuj w Console (Billing) stan kredytu i salda.

**Kroki:**
```text
~/.claude/skills/maestro/bin/maestro-sdk --resolve haiku
/maestro --sdk --plan-only --critic=sol dodaj funkcję slugify z testami
```

**Oczekuję:** linia przydziału z `transport=api` dla slotów Claude. W `.maestro/ledger.jsonl`
wiersze `cli: claude-sdk` z `cost_usd`, raport z kwotą w USD. Po kilku minutach Console pokazuje
ubytek kredytu, a saldo stoi w miejscu.

**Odeślij:** wynik `--resolve`, linię przydziału, sumę `cost_usd` z raportu i to, co pokazała
Console (kredyt czy saldo, ile).

### 8. Przełączenie native → api po wyczerpaniu limitu

**Cel:** transport-switch na `api` w trakcie przebiegu.

**Gdzie:** jak w 7, z `api: {fallback: true}` w `~/.config/maestro/policy.yml`. Shim `claude` z
`tests/canary/shim/claude` udaje wyczerpany limit.

**Oczekuję:** `transport: sonnet native→api (quota; …)`, wiersz ledgera `transport-switch`,
dokończony build na `api`, testy uruchomione przez dyrygenta.

**Odeślij:** linię przełączenia i wiersze ledgera.

## Sprzątanie

```bash
rm -r ~/maestro-checks
```
