# route2

Wielomodelowa pętla budowania dla agentów kodujących. Model, z którym rozmawiasz, zostaje
**dyrektorem**: przeprowadza wywiad, pisze plan, oddaje plan do krytyki modelom z **innych rodzin**,
przekazuje budowę wykonawcy dopasowanemu do zadania, bramkuje i testuje wynik, commituje i raportuje,
kto co zrobił i ile to kosztowało.

route2 to osobny fork route 3.4.0 (repozytorium `route-skill`). Co dodaje:

- **Cztery hosty.** Działa jako dyrektor w **Claude Code**, **Codex**, **`agent` Cursora** i **agy**
  (Antigravity CLI), rozpoznaje, w którym jest, i dopasowuje sposób uruchamiania workerów, czekania
  na nich i zadawania pytań.
- **Cztery rodziny modeli, więcej dróg dojścia.** Claude, OpenAI, Google i nowa **xAI** (Grok przez
  Cursora). Do modeli Claude prowadzą cztery drogi — subagenci Claude Code, `claude -p`, agy i
  Cursor — i route2 przechodzi po nich w tej kolejności, gdy któraś wyczerpie limit.
- **Żywy katalog.** Slot to *linia* modeli (`sol` = najnowszy `gpt-*-sol`), rozwiązywana na starcie
  każdego runu z katalogów samych CLI i sprawdzana probem — nowy Opus czy Sol nie wymaga edycji
  skilla.
- **Skrypty pomocnicze** (`bin/`, bash + jq) do tego, czego sam skill w markdownie nie zrobi
  niezawodnie: wykrywanie hosta, blokada z generacją, zadania w tle przeżywające sesję dyrektora,
  walidacja werdyktów, odcisk tylko-do-odczytu, deterministyczny dobór ról.

Bez SDK: zarówno Codex SDK, jak i Claude Agent SDK tylko opakowują CLI, którymi route2 i tak steruje.

## Wykonawcy

| Rodzina | Sloty | Przez |
| --- | --- | --- |
| Claude | `opus`, `fable`, `sonnet`, `haiku` | narzędzie `Agent` w Claude Code albo `claude -p` → agy → Cursor |
| OpenAI | `astra`, `sol`, `luna`, `terra` (tylko jawnie) | `codex exec` |
| Google | `gemini` (Flash) | `agy` |
| xAI | `grok` (tymczasowo — jeszcze niezmierzony jako builder) | `agent -p` Cursora |

Modele z jednej rodziny mają wspólne ślepe plamki, więc **żaden krytyk planu ani recenzent nie
pochodzi z rodziny buildera, którego kod trafia do commita** (z określonymi zastępstwami, gdy
rodzin jest mniej).

## Instalacja

```bash
git clone <to repozytorium> && cd route2-skill
./install.sh                   # ~/.agents/skills/route2 (Codex, Cursor) + linki dla Claude Code i agy
./install.sh ~/code/my-app     # do jednego projektu
./install.sh --check           # gdzie jest zainstalowany
./install.sh --check=live      # każdy host wypisuje swoje skille (tanie wywołania headless)
```

Wymagania: Linux, bash ≥ 5, jq ≥ 1.6, git, util-linux (`setsid`, `flock`) i te z `claude`, `codex`,
`agent`, `agy`, których chcesz używać, zalogowane. Starszy skill `/route` nie jest ruszany; **nie
uruchamiaj `/route` i `/route2` jednocześnie w tym samym checkoucie** (route nie widzi blokady
route2).

## Użycie

| Host | Wywołanie | Czego dyrektor potrzebuje |
| --- | --- | --- |
| Claude Code | `/route2 <zadanie>` | nic |
| Codex | `$route2 <zadanie>` | Codex uruchomiony z `--sandbox danger-full-access` (komendy dyrektora muszą dosięgnąć API modeli i uruchomić testy) |
| Cursor (`agent`) | `/route2 <zadanie>` | projektowy `.cursor/cli.json` pozwalający na skrypty route2, `git`, `jq` i komendę testów — nigdy `--force` (zob. `docs/hosts.md`) |
| agy | `/route2 <zadanie>` | sesja interaktywna (tryb print nie uruchamia komend); zatwierdzaj komendy albo dodaj reguły `permissions.allow` |

Bez interakcji (`claude -p`, `codex exec`, `agent -p`) — tylko z `--unattended`.

```text
/route2 dodaj eksport faktur do CSV
/route2 --model=grok --critic=sol,opus --review=cross podziel generator raportów na joby
/route2 opus przez agy napraw paginację                 # wymuszenie drogi dojścia
/route2 --setup <zadanie>                                # konfiguracja pytaniami
/route2 --plan-only <zadanie>                            # plan + krytyka, bez budowy
/route2 --resume                                         # kontynuacja po limicie albo zamkniętym laptopie
```

Flagi i polityka: jak w [README.md](README.md); dokumentacja jest po angielsku w [docs/](docs/).
