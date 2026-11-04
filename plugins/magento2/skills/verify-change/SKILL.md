---
name: verify-change
description: Verify a Magento 2 change on the local environment with evidence — decide per test case whether it needs a real browser (storefront Hyvä/Luma/PWA, admin, checkout, emails) or a non-browser check (GraphQL/REST, CLI, cron, DB read, logs), then run it with Playwright MCP or the container CLI and record the result. Use when executing QA test cases, smoke-testing a change, or when asked to check or click through a change in the browser ("sprawdź w przeglądarce", "przeklikaj"). Works standalone or inside the delivery pipeline.
argument-hint: "[co sprawdzić — opis zmiany, AC lub klucz Jira]"
---

# Weryfikacja zmiany (QA)

Sprawdzasz zmianę na **lokalnym** środowisku. Nigdy staging/produkcja bez wprost nazwanego środowiska przez użytkownika. Wynik każdego sprawdzenia ma dowód. Zakres: $ARGUMENTS (albo to, co wskazał użytkownik / orkiestrator).

## 0. Tryb i środowisko

**Tryb:**
- **Pipeline** — wywołuje Cię agent `delivery:qa` (jest plik `var/agents/.current` i `03-test-plan.md` zadania). Przypadki bierzesz z planu testów, wyniki zapisujesz w `06-qa.md`, `<KLUCZ>` = klucz zadania.
- **Samodzielnie** — wszystko inne. Przypadki ustalasz sam z opisu zmiany / AC / `git diff` (pokaż listę użytkownikowi przed wykonaniem), wynik raportujesz w czacie (format w sekcji 5). `<KLUCZ>` = klucz Jira z gałęzi lub z prośby, a gdy go brak — krótki opis, np. `QA-cart-badge-`.

**Środowisko** (`<URL>`, `<EXEC>`, `<DB>`, frontend):
1. `CLAUDE.md` zawiera sekcję „Środowisko lokalne” (generuje ją `/delivery:init`) → bierzesz wartości stamtąd.
2. W przeciwnym razie uruchom `magento2-detect "$CLAUDE_PROJECT_DIR"` (komenda z pluginu `magento2`) i przyjmij:

   | `ENV_TOOL` | `<EXEC>` | `<DB>` |
   |---|---|---|
   | `warden` | `warden env exec -T php-fpm` | `warden db connect` |
   | `reward` | `reward env exec -T php-fpm` | `reward db connect` |
   | `ddev` | `ddev exec` | `ddev mysql` |

   `<URL>` = `BASE_URL`. Brak lub kilka kandydatów → zapytaj użytkownika. Pokaż przyjęte wartości jednym zdaniem i działaj dalej.
3. Środowisko nie działa (`<EXEC> php -v` zwraca błąd) → zatrzymaj się i powiedz to użytkownikowi; nie uruchamiaj środowiska sam bez zgody.

## 1. Wybór metody — dla każdego przypadku testowego

| Co zmienia zadanie | Metoda | Przeglądarka? |
|---|---|---|
| Szablony `.phtml`, layout XML, CSS/JS, Alpine/Knockout, komponenty PWA | renderowanie + interakcja | **tak** |
| Checkout, koszyk, konto klienta, formularze | przepływ użytkownika | **tak** |
| Admin: formularze, gridy, konfiguracja, ACL widoczne w UI | przepływ w adminie | **tak** |
| Maile transakcyjne | wywołanie + webmail środowiska | **tak** (webmail) |
| Resolver GraphQL / endpoint REST | `curl` na `<URL>/graphql` lub `/rest/...` | nie (dla PWA dodatkowo przeglądarka, jeśli AC dotyczy UI) |
| Cron, konsumer kolejki, komenda CLI, import | `<EXEC> bin/magento ...`, logi, odczyt bazy | nie |
| Obserwatory/pluginy bez UI | wyzwolenie akcji (CLI/API/UI) + odczyt efektu w bazie/logu | zależnie od wyzwalacza |
| Indeksy, cache, FPC | flush/reindex + porównanie odpowiedzi (nagłówki `X-Magento-Cache-*`) | opcjonalnie |

Zasada: przeglądarka, gdy AC opisuje coś, co **widzi lub klika człowiek**. W przeciwnym razie najtańsza deterministyczna metoda. Gdy oba — oba.

## 2. Przygotowanie
1. Kroki wdrożeniowe: w pipeline z `04-implementation.md`; samodzielnie — wynikające z diffu (nowy `db_schema.xml`/patch → `setup:upgrade`, `di.xml` → `cache:flush`, zawsze `cache:flush` przed testem). Komendy zmieniające stan pokaż przed uruchomieniem.
2. Zanotuj liczbę linii logów (`<EXEC> wc -l var/log/exception.log var/log/system.log`), żeby po teście wskazać tylko nowe wpisy.
3. Dummy data: wyłącznie syntetyczne, prefiks `QA-<KLUCZ>-`, e-maile w `example.com`, tworzone przez API/CLI Magento. Każdy rekord od razu do tabeli „Dummy data” (w pipeline: `06-qa.md`; samodzielnie: w raporcie). Zakaz DROP/TRUNCATE/ALTER, DELETE/UPDATE bez WHERE i surowych zapisów SQL do rekordów spoza dummy data — poza pipeline'em nie pilnuje tego żaden hook.

## 3. Przeglądarka (Playwright MCP z pluginu `magento2`)
Narzędzia: `mcp__plugin_magento2_playwright__*`. Typowe: `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_fill_form`, `browser_select_option`, `browser_wait_for`, `browser_console_messages`, `browser_network_requests`, `browser_take_screenshot`, `browser_resize`, `browser_tabs`, `browser_close`.

Dla każdego przypadku:
1. `browser_navigate` na URL z `CLAUDE.md` (certyfikaty lokalne są akceptowane — serwer ma `--ignore-https-errors`).
2. `browser_snapshot` przed interakcją — klikaj po referencjach ze snapshotu, nie po zgadywanych selektorach.
3. Wykonaj kroki z planu testów. Po każdej akcji, która ładuje dane (AJAX, GraphQL w PWA), `browser_wait_for` na oczekiwany tekst/element.
4. Sprawdź:
   - oczekiwany wynik z planu (tekst, stan, cena, komunikat),
   - `browser_console_messages` — błędy JS = defekt, chyba że występowały przed zmianą (sprawdź na stronie bez zmiany),
   - `browser_network_requests` — odpowiedzi 4xx/5xx i błędy w odpowiedziach GraphQL (`errors` w JSON),
   - widok mobilny, jeśli zakres obejmuje frontend: `browser_resize` 375×812, potem z powrotem 1440×900.
5. Dowód: `browser_take_screenshot` z nazwą `<ID-przypadku>-<krok>.png`; przy wyniku zapisz ścieżkę pliku zwróconą przez narzędzie. Zrzut nie może pokazywać danych osobowych ani prawdziwych zamówień — tylko dummy data.
6. FPC: dla stron cache'owalnych sprawdź wynik dwa razy — po `cache:flush` i przy drugim wejściu (strona z cache).

### Logowanie
- **Admin:** nie wpisuj hasła w narzędziach ani nie zapisuj go w plikach. Otwórz `/<admin-path>` w przeglądarce Playwright i poproś użytkownika, żeby zalogował się ręcznie w otwartym oknie; sesja zostaje w profilu przeglądarki na czas pracy. Ścieżkę admina weź z `<EXEC> bin/magento info:adminuri`.
- **Klient sklepu:** konto dummy `QA-<KLUCZ>-...@example.com` utworzone przez API/CLI. Hasło generuj losowo w sesji, nie zapisuj go w plikach przekazania ani w Jira; po teście konto usuwasz razem z dummy data.

### Gdy przeglądarka nie działa
Serwer Playwright nie startuje (brak `npx`/przeglądarki) lub strona nie odpowiada → nie zgaduj wyniku. Oznacz przypadek „NIE WYKONANO — <powód>”, dopisz pytanie do „Otwartych pytań” i zakończ ze statusem FAIL (kryterium „wykonano wszystkie przypadki” nie jest spełnione).

## 4. Bez przeglądarki
- GraphQL: `curl -sk -X POST <URL>/graphql -H 'Content-Type: application/json' -d '{"query":"..."}'`. Dla zapytań per store dodaj nagłówek `Store: <code>`. Sprawdź `data` i brak `errors`.
- REST: `curl -sk <URL>/rest/<store>/V1/...`; tokeny tylko przez `op read` lub od użytkownika — nigdy wpisane w komendę jawnym tekstem.
- CLI/cron: `<EXEC> bin/magento cron:run --group=<grupa>` lub komenda modułu; odczyt efektu `<DB> -e "SELECT ... WHERE ... LIKE 'QA-<KLUCZ>-%'"`.
- Wynik z bazy streszczaj (liczby, ID dummy data), nie wklejaj surowych wierszy.

## 5. Po teście
- Nowe wpisy w `var/log/exception.log` / `system.log` od zanotowanej linii → przy każdym przypadku: „brak” albo streszczenie (klasa wyjątku, komunikat bez danych osobowych).
- Wynik przypadku: PASS / FAIL / NIE WYKONANO, z dowodem (plik zrzutu, odpowiedź API w skrócie, komenda + wynik).
- Defekt: kroki odtworzenia, oczekiwane, faktyczne, waga (Krytyczny / Wysoki / Niski), dowód.
- Zamknij kartę przeglądarki (`browser_close`) po zakończeniu rundy.

### Raport w trybie samodzielnym
```
Środowisko: <ENV> · <URL> · frontend: <...>
| ID | Co sprawdzono | Metoda | Wynik | Dowód | Uwagi |
Defekty: | ID | Kroki odtworzenia | Oczekiwane | Faktyczne | Waga |
Nowe wpisy w logach: brak | <streszczenie>
Dummy data: | Typ | Identyfikator | Store |
```
Na końcu zapytaj, czy usunąć dummy data; usuwasz wyłącznie rekordy z tabeli, po ID/prefiksie. W pipeline sprzątanie zleca orkiestrator.
