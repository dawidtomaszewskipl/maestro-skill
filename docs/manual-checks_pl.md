# Ręczne sprawdzenia maestro

Automatyczne testy i pomiary z 11.10.2026 pokryły wszystkie cztery hosty, ale kilku rzeczy nie dało
się sprawdzić bez Ciebie. Część wymaga sesji interaktywnej, część limitów, których nie da się
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

**Cursor potrzebuje listy dozwolonych komend** (przypadki 4–6). W katalogu repozytorium:

```bash
mkdir -p .cursor
jq -n --arg p "$PWD/.agents/skills/maestro" --arg g "$HOME/.agents/skills/maestro" '
  {permissions: {
     allow: ([$p, $g] | map(. as $m | ["host","lock","run","wait","kill","env","catalog","state","fp",
                                        "validate","roles","ledger"] | map("Shell(\($m)/bin/maestro-\(.))")) | add)
            + (["codex","agy","agent","claude","git","jq","bash","cat","ls","mkdir","printf","echo",
                "grep","sed","head","tail","wc","date","sha256sum","readlink","dirname","command","test"]
               | map("Shell(\(.))")),
     deny: []}}' > .cursor/cli.json
```

`Shell(bash)` jest tu potrzebne, bo test to `bash tests/test_str.sh`, ale w praktyce otwiera
wszystko, co da się zrobić przez `bash -c`. W prawdziwym projekcie wpisz zamiast niego swoją
komendę testów. Nigdy nie uruchamiaj `agent` z `--force`.

## Kolejność

Najwięcej powiedzą przypadki 1, 4, 5 i 11. Przypadki 2, 3 i 10 zrób przy okazji, gdy nadarzy się
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

### 3. Claude przez Cursora (gdy odnowi się limit)

**Cel:** droga Claude przez Cursora nie była sprawdzona, bo limit jest wyczerpany.

**Gdzie:** interaktywny Claude Code w nowym repozytorium testowym.

**Kroki:**
```text
/maestro --model=sonnet@cursor --critic=sol --rounds=1 <zadanie>
```

**Oczekuję:**
- przy odnowionym limicie: `sonnet=… (cursor)`, budowa w piaskownicy Cursora, commit;
- przy wyczerpanym limicie: run **staje z pytaniem** (`@cursor` wymusza drogę, więc maestro nie
  może sam przejść na inną). Ciche przejście na inną drogę byłoby błędem.

**Odeślij:** który wariant wystąpił i linię przydziału albo treść pytania.

### 4. Grok jako wykonawca

**Cel:** Grok był mierzony tylko jako krytyk. Trzeba sprawdzić, czy umie zbudować i czy
uruchamia testy w swojej piaskownicy.

**Gdzie:** interaktywny Claude Code w nowym repozytorium testowym. Plik `.cursor/cli.json` nie jest
tu potrzebny, bo dyrygentem jest Claude Code.

**Kroki:**
```text
/maestro --model=grok --critic=sol --rounds=1 --review=cross <zadanie>
```

**Oczekuję:**
- przy wykonawcy pojawia się `grok=grok-4.7-… (cursor) (provisional)`;
- zmiana dotyczy tylko `lib/str.sh` i `tests/test_str.sh`;
- testy przechodzą, a recenzent z innej rodziny ocenia wynik.

**Odeślij:** czy kod był dobry przy pierwszym podejściu, ile było rund poprawek i czy testy
uruchamiał Grok, czy dyrygent (to widać w raporcie).

### 5. Dyrygent w Cursorze, interaktywnie

**Cel:** sprawdzić codzienną pracę z Cursorem: pytania, monity o uprawnienia i to, że dyrygent nie
buduje sam.

**Gdzie:** nowe repozytorium testowe z `.cursor/cli.json` (patrz „Przygotowanie”), w terminalu:
`agent`.

**Kroki:**
```text
/maestro --model=sonnet --critic=grok --rounds=1 <zadanie>
```
Potem, w tej samej sesji, `/maestro --model=self <zadanie>`.

**Oczekuję:**
- host `cursor`, pytania zadawane zwykłym tekstem;
- przy `--model=self` odmowa z wyjaśnieniem, że w Cursorze nie da się ustalić modelu dyrygenta;
- brak monitów o komendy spoza listy. Jeśli jakiś monit się pojawi, to znaczy, że lista jest
  niepełna.

**Odeślij:** każdy monit o uprawnienie (jaka komenda) i swoje wrażenia z pytań.

### 6. Dyrygent w agy, bez automatycznego zatwierdzania

**Cel:** w pomiarach monity agy zatwierdzał skrypt. Trzeba sprawdzić, jak to wygląda dla człowieka
i czy da się z tym pracować.

**Gdzie:** nowe repozytorium testowe, w terminalu: `agy`.

**Kroki:**
```text
/maestro --model=sol --critic=opus --rounds=1 <zadanie>
```
Zatwierdzaj komendy i zapisy plików w obrębie repozytorium.

**Oczekuję:**
- pytania o komendy i o zapis plików (`.maestro/…`, `lib/str.sh`);
- run kończy się commitem;
- odmowa dostępu poza repozytorium kończy turę agy, wtedy wystarczy napisać „kontynuuj”.

**Odeślij:** ile mniej więcej było monitów i czy któryś był niezrozumiały. Na tej podstawie
przygotuję reguły `permissions.allow`, żeby było ich mniej.

### 7. Dyrygent w Codex, interaktywnie

**Cel:** pomiary były robione przez `codex exec` (bez interakcji). Trzeba sprawdzić pytania
w interaktywnym Codex.

**Gdzie:** nowe repozytorium testowe, w terminalu: `codex --sandbox danger-full-access`.

**Kroki:**
```text
$maestro --setup <zadanie>
```

**Oczekuję:**
- host `codex`, dyrygent rozpoznany (np. `gpt-6.1-sol`);
- pytania konfiguracyjne w oknie wyboru albo zwykłym tekstem;
- krytycy spoza rodziny OpenAI.

**Odeślij:** jak wyglądały pytania i linię przydziału.

### 8. Wznowienie na innym hoście

**Cel:** zmiana hosta przy `--resume` nie była mierzona, wszystkie wznowienia były na tym samym.

**Gdzie:** nowe repozytorium testowe.

**Kroki:**
1. Uruchom w Codex (`codex --sandbox danger-full-access`):
   `$maestro --model=sonnet --critic=gemini --rounds=1 <zadanie>`.
2. Gdy zacznie się budowa, zamknij Codex (dwa razy Ctrl+C).
3. Otwórz w tym samym repozytorium Claude Code i wpisz `/maestro --resume`.

**Oczekuję:**
- maestro mówi, że host się zmienił (codex → claude-code), i wymienia, co to zmienia (kto może
  budować, krytycy), a potem pyta o zgodę;
- po zgodzie: budowa, która trwała w tle, zostaje odnaleziona i dokończona, potem testy i commit.

**Odeślij:** komunikat o zmianie hosta i raport końcowy.

### 9. Dwa runy w jednym repozytorium

**Cel:** sprawdzić, że blokada repozytorium działa także między hostami.

**Kroki:** w jednym terminalu uruchom `/maestro <zadanie>` w Claude Code. Gdy zacznie pracować,
w drugim terminalu w tym samym repozytorium uruchom `$maestro <zadanie>` w Codex.

**Oczekuję:** drugi run odmawia startu i mówi, kto trzyma blokadę (identyfikator runu, host).
Pierwszy pracuje dalej bez zakłóceń.

**Odeślij:** komunikat odmowy.

### 10. Nowy model (przy okazji)

**Cel:** sprawdzić najważniejszą obietnicę: nowy model bez edycji skilla.

**Kiedy:** po premierze nowego modelu (np. nowy Sol, Opus, Gemini Flash albo Grok).

**Oczekuję:** w najbliższym runie linia przydziału pokazuje nową wersję. Jeśli Twoje konto nie ma
do niej dostępu, zobaczysz dopisek w rodzaju `(gpt-6.2-sol listed, denied for this account)`
i użytą starszą wersję.

**Odeślij:** linię przydziału.

### 11. Pierwszy run w prawdziwym projekcie

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

## Sprzątanie

```bash
rm -r ~/maestro-checks
```
