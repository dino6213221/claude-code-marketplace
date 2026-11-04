# Kontekst projektu (wspólny dla wszystkich agentów)

<!-- Wygenerowane przez /delivery:init z .claude/delivery.json. Zmiany środowiska: popraw delivery.json i uruchom init ponownie. -->

## Stack
- Magento 2 / Adobe Commerce, MSI, multi-store / multi-language.
{{FRONTEND_RULES}}
- Wersja PHP: {{PHP}}. NIGDY nie używaj składni ani funkcji nowszych niż najniższa wspierana wersja projektu.
- Katalog Magento (względem katalogu projektu): `{{MAGENTO_ROOT}}`. Kod własny: `{{MAGENTO_ROOT}}/app/code/<Vendor>/<Module>`. Nie modyfikuj `vendor/` ani `generated/`.

## Środowisko lokalne: {{ENV_NAME}}
- Wszystkie komendy PHP/Magento uruchamiaj w kontenerze (katalog roboczy kontenera = katalog Magento):
  - `{{EXEC}} bin/magento <komenda>`
  - `{{EXEC}} composer <komenda>`
  - `{{EXEC}} vendor/bin/phpunit ...`
  - `{{EXEC}} vendor/bin/phpcs --standard=Magento2 <ścieżka>`
- Baza: `{{DB}} -e "<SELECT ...>"` (tylko odczyt, chyba że zadanie QA tego wymaga — patrz zasady danych).
- URL sklepu: {{BASE_URL}}
- Maile testowe: {{MAIL_URL}}
- Nie zatrzymuj środowiska z usuwaniem wolumenów, nie usuwaj środowiska i nie importuj baz bez zgody użytkownika.
- NIE używaj `isolation: worktree` ani osobnych worktree: środowisko serwuje sklep z głównego checkoutu, więc kod w worktree byłby niewidoczny dla smoke testów i QA.

## Środowiska
- Pracujemy WYŁĄCZNIE na lokalnym środowisku ({{ENV_NAME}}). Staging tylko, gdy użytkownik wprost go nazwie. Produkcja — nigdy.

## Bezpieczeństwo i dane (zasady FWC)
- Sekrety tylko przez 1Password (`op run`, `op read "op://Vault/Item/field"`). Nigdy nie wypisuj haseł/tokenów w plikach, komendach, commitach ani w Jira.
- Dane klienta są poufne. Nie wklejaj surowych wierszy z bazy ani logów do Jira, PR-ów, ani plików przekazania — streszczaj i pseudonimizuj.
- MCP: agenci mogą korzystać z serwerów MCP skonfigurowanych w projekcie (obecnie: Atlassian — jako serwer projektu `atlassian`, konektor claude.ai lub plugin `atlassian`; Playwright dostarcza plugin `magento2`, w pipeline używa go QA). Odczyt działa bez pytań, każda operacja zapisu w systemach zewnętrznych wymaga zgody użytkownika. Nowy serwer MCP → najpierw sprawdź, czy jest na liście „Approved Tools”, wersję przypinaj dokładnie (bez `@latest`).
- Używaj tylko narzędzi z listy FWC „Approved Tools” (Confluence). Spoza listy → stop i pytanie.
- Operacje destrukcyjne (DROP/TRUNCATE, DELETE/UPDATE bez WHERE, `rm -rf`, force-push, `reset --hard`, pominięcie hooków) → wymagają potwierdzenia użytkownika z nazwą środowiska.
- Reguły biznesowe: źródłem są Jira/Confluence. Kod = obecne zachowanie, Confluence/Jira = zamierzone. Rozbieżność → zgłoś, nie rozstrzygaj sam. Nigdy nie wymyślaj reguł.

## Pliki przekazania
- Katalog: `{{MAGENTO_ROOT}}/var/agents/<KLUCZ>/` (ignorowany przez git). Każda ścieżka `var/agents/...` w definicjach agentów i orkiestratora oznacza `{{MAGENTO_ROOT}}/var/agents/...` względem katalogu projektu.
- Plik `var/agents/.current` zawiera klucz bieżącego zadania (zapisuje go orkiestrator; czyta hook walidujący).
- Pliki i dozwolone statusy:
  - `01-analysis.md` — READY | BLOCKED | TOO_LARGE
  - `02-architecture.md` — READY | NEEDS_INPUT | TOO_LARGE
  - `03-test-plan.md` — READY | NEEDS_INPUT
  - `04-implementation.md` — DONE | NEEDS_INPUT
  - `05-review.md` — APPROVED | CHANGES_REQUESTED
  - `06-qa.md` — PASS | FAIL
  - `07-retro.md` — (bez statusu)
- Każdy plik zaczyna się linią `STATUS: <wartość>`, ma sekcję `## Kryteria sukcesu` (checklista `[x]`/`[ ]`) i `## Otwarte pytania` w formacie `- → <agent>: <pytanie>` (lub „brak”).
- Status pozytywny przy jakimkolwiek `[ ]` jest odrzucany automatycznie przez hook `SubagentStop`.
- Dowody QA: ścieżki zrzutów Playwright i streszczenia wyników zapisuje QA w `06-qa.md`.
- Po zamknięciu zadania katalog `var/agents/<KLUCZ>/` jest usuwany.

## Pamięć agentów
- Solution Architect i Code Reviewer mają pamięć `local` (`.claude/agent-memory-local/`, poza gitem, per projekt — dzięki temu wiedza o jednym kliencie nie trafia do innego).
- W pamięci zapisuj wyłącznie wiedzę techniczną o projekcie (konwencje, pułapki, powtarzające się uwagi). Nigdy danych klienta, danych osobowych ani sekretów.
