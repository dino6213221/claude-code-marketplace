---
name: init
description: Prepare the current project for the delivery agent pipeline — detect Magento root, local environment (Warden / Reward / DDEV) and frontend, save them in .claude/delivery.json, then merge generated permissions into .claude/settings.json, the agent context into CLAUDE.md and entries into .gitignore. Run once per project (and again after the environment changes) before /delivery:deliver.
disable-model-invocation: true
---
Przygotowujesz bieżący projekt do pracy z pipeline'em `/delivery:deliver`. Plugin nie może sam instalować ustawień projektu, więc generujesz je ze szablonów pluginu dla wykrytego środowiska.

Pliki pluginu:
- `magento2-detect` — komenda z pluginu `magento2` (jest na PATH, bo `delivery` od niego zależy); wykrywa układ projektu, wypisuje `KEY=VALUE`
- `${CLAUDE_PLUGIN_ROOT}/scripts/render.sh` — z `.claude/delivery.json` generuje `settings.json` i sekcję `CLAUDE.md`
- `${CLAUDE_PLUGIN_ROOT}/templates/gitignore-snippet` — wpisy do `.gitignore`

## Zasady
- Niczego nie nadpisujesz w całości. Każdy plik docelowy najpierw czytasz, potem pokazujesz użytkownikowi planowaną zmianę (diff) i czekasz na akceptację, osobno dla każdego pliku.
- Nie usuwasz istniejących reguł, wpisów ani sekcji (wyjątek: podmiana własnej, wcześniej wygenerowanej sekcji w `CLAUDE.md` — patrz krok 5).
- Nie czytasz `app/etc/env.php`, `auth.json` ani wartości sekretów z `.env`. Nie commitujesz.
- Pliki robocze trzymasz w katalogu tymczasowym sesji, nie w repo.

## Kroki
1. **Katalog projektu**: `$CLAUDE_PROJECT_DIR` (lub katalog roboczy sesji). Potwierdź go z użytkownikiem.
2. **Wykrywanie**: `magento2-detect "<katalog projektu>"`. Komenda nie istnieje → plugin `magento2` jest wyłączony; poproś o `/plugin install magento2@daniel-marketplace`.
   Pokaż wynik jako tabelę i zbierz brakujące lub niejednoznaczne wartości:
   - `MAGENTO_ROOT` puste → zapytaj (katalog z `bin/magento`, względem projektu),
   - `ENV_CANDIDATES` zawiera kilka narzędzi albo `ENV_TOOL` puste → zapytaj, którego środowiska używa (`warden` | `reward` | `ddev`),
   - `FRONTEND` puste lub niepewne → zapytaj (`hyva`, `luma`, `pwa`; może być kilka),
   - `BASE_URL`, `MAIL_URL`, `PHP_CONSTRAINT` puste → zaproponuj wartość lub zostaw pustą (agenci zapytają w trakcie).
3. **Konfiguracja**: zapisz `.claude/delivery.json` (pokaż przed zapisem):
   ```json
   {
     "magentoRoot": "app/magento",
     "env": "warden",
     "baseUrl": "https://app.example.test/",
     "mailUrl": "https://webmail.example.test/",
     "frontend": ["hyva"],
     "php": ">=8.1"
   }
   ```
   Plik jest bez sekretów — może trafić do repo, jeśli zespół używa tego samego środowiska. Jeśli już istnieje, pokaż różnice i zapytaj, które wartości zmienić.
4. **Generowanie**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render.sh" "<projekt>/.claude/delivery.json" "<katalog tymczasowy>"`.
5. **`.claude/settings.json`**:
   - brak pliku → utwórz z wygenerowanego,
   - plik istnieje → scal: `env` (klucze tylko gdy ich brak), `permissions.allow|deny|ask` (suma list bez duplikatów), `permissions.defaultMode` tylko gdy brak. Pozostałe klucze projektu bez zmian. Możesz użyć `jq -s`.
   - Konflikt (ta sama reguła w `allow` i `deny`, albo reguły starego środowiska po zmianie `env`) → pokaż i zapytaj.
6. **`CLAUDE.md`** w katalogu projektu:
   - sekcja zaczyna się nagłówkiem `# Kontekst projektu (wspólny dla wszystkich agentów)`;
   - brak sekcji → dopisz wygenerowaną na końcu pliku (lub utwórz plik),
   - sekcja istnieje (poprzedni init) → pokaż diff i za zgodą podmień ją w całości, aż do następnego nagłówka `# ` pierwszego poziomu lub końca pliku.
7. **`.gitignore`**: dopisz brakujące linie z `gitignore-snippet`. Sprawdź, czy katalog przekazania jest ignorowany: `git check-ignore -q "<magentoRoot>/var/agents/x"`; jeśli nie — dopisz `<magentoRoot>/var/agents/`.
8. **Sprawdzenie środowiska** (jeśli kontenery działają; jeśli nie — pomiń i zgłoś):
   - `<EXEC> php -v` i `<EXEC> ls bin/magento` — potwierdza prefiks komend i katalog roboczy kontenera; błąd → pokaż i zapytaj o poprawny prefiks,
   - `HAS_JQ=no` → hooki pipeline'u nie działają w pełni (`brew install jq`),
   - `HAS_NPX=no` → serwer Playwright z pluginu `magento2` (QA w przeglądarce) nie wystartuje; potrzebny Node.js.
9. **Podsumowanie**: co zmieniono w każdym pliku, co pominięto i dlaczego. Przypomnij o `/reload-plugins` lub restarcie sesji, żeby uprawnienia i `CLAUDE.md` zaczęły obowiązywać.
