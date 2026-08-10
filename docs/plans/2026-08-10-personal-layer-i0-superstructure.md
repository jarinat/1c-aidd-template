# И0: переориентация личного слоя на надстройку — план реализации

> **Для агента-исполнителя:** выполняй задачу за задачей, каждая заканчивается
> проверкой и коммитом. Шаги отмечены чекбоксами `- [ ]`.

**Цель:** сделать `1c-aidd-template` надстройкой над корпоративным слоем
`mpl-*`: перенести обе личные входные точки с имён, принадлежащих
корпоративному слою, и запретить установку личного слоя в проект без
корпоративного.

**Архитектура:** личный слой перестаёт претендовать на `.claude/CLAUDE.md` и
`AGENTS.md`. Его точки входа — корневой `CLAUDE.local.md` (Claude Code) и
`.agents/local/instructions.md` (Codex); оба пути gitignored в рабочем проекте и
явно предусмотрены корпоративным слоем. Оба скрипта доставки получают проверку
предусловия.

**Стек:** PowerShell 5.1+ (`tools/*.ps1`), Markdown.

Спека: [`../specs/2026-08-10-personal-layer-consolidation-design.md`](../specs/2026-08-10-personal-layer-consolidation-design.md).

## Глобальные ограничения

- Репозиторий работ: `C:/Users/jarin/git/my-projects/1c-aidd-template`.
- Ветка: `main`. Это сложившаяся практика репозитория — 20 неотправленных
  коммитов на `main`, отдельные ветки не заводились. Отклонение от общего
  правила «ветка перед коммитом» осознанное; если нужна ветка, завести до
  Задачи 1.
- Целевой проект для проверок: `C:/Users/jarin/git/sollers/MBS` — единственный
  включённый в `config/projects.local.json`.
- Язык сообщений в `tools/*.ps1` — английский, по сложившемуся стилю этих
  скриптов (`"Template sync root does not exist"`, `"Project is disabled in
  config/projects.local.json"`). Русский язык корпоративного стандарта относится
  к корпоративному слою, а не к этому репозиторию.
- Ни один шаг не изменяет `.claude/CLAUDE.md` и `AGENTS.md` в MBS.
- `-Apply` в MBS выполняется только в Задаче 5, после сверки содержания.

## Структура изменений

| Файл | Ответственность после И0 |
|---|---|
| `tools/sync-to-project.ps1` | доставка runtime-слоя; отказ без корпоративного слоя |
| `tools/bootstrap-project.ps1` | первичная установка; тот же отказ; больше не владеет `AGENTS.md` |
| `template/project/CLAUDE.local.md` | личная точка входа Claude Code (переехала из `.claude/CLAUDE.md`) |
| `template/project/.agents/local/instructions.md` | личная точка входа Codex (переехала из `AGENTS.md`) |
| `README.md` | описание шаблона как надстройки |

---

### Задача 1: Проверка предусловия в обоих скриптах

**Файлы:**
- Изменить: `tools/sync-to-project.ps1` (функции — после `Resolve-Directory`,
  вызов — после присвоения `$targetProject`, строка 112)
- Изменить: `tools/bootstrap-project.ps1` (вызов — после присвоения
  `$targetProject`, строка 234)

**Интерфейсы:**
- Производит: функцию `Assert-CorporateLayer -ProjectRoot <path>`, которую
  используют оба скрипта. Бросает исключение, если корпоративного слоя нет.

- [ ] **Шаг 1: Подготовить каталог для негативной проверки**

Каталог заведомо без корпоративного слоя. Использовать scratchpad сессии, не
`/tmp` и не рабочие репозитории. Ниже `SCRATCH` — каталог scratchpad текущей
сессии; в сессии, где план писался, это
`C:/Users/jarin/AppData/Local/Temp/claude/c--Users-jarin-git-sollers-MBS/8a8f1c0a-6e6b-43f5-8510-9028797b727c/scratchpad`.

```bash
mkdir -p "<SCRATCH>/no-corp-project"
```

- [ ] **Шаг 2: Убедиться, что сейчас проверки нет (тест падает)**

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath "<SCRATCH>/no-corp-project"
```

Ожидается: скрипт **отрабатывает** и печатает список `Add` — то есть готов
установить личный слой в проект без корпоративного. Это и есть дефект.

- [ ] **Шаг 3: Добавить функцию в `sync-to-project.ps1`**

Вставить после функции `Resolve-Directory` (перед `Join-TemplatePath`):

```powershell
function Assert-CorporateLayer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $agentsEntrypoint = Join-Path -Path $ProjectRoot -ChildPath "AGENTS.md"
    $corporateSkills = Join-Path -Path $ProjectRoot -ChildPath ".agents/skills"

    if (-not (Test-Path -LiteralPath $agentsEntrypoint -PathType Leaf)) {
        throw "Corporate agent layer is missing in target project (no AGENTS.md). The personal AIDD layer is a superstructure and cannot be installed without it: $ProjectRoot"
    }

    if (-not (Test-Path -LiteralPath $corporateSkills -PathType Container)) {
        throw "Corporate agent layer is missing in target project (no .agents/skills). The personal AIDD layer is a superstructure and cannot be installed without it: $ProjectRoot"
    }
}
```

- [ ] **Шаг 4: Вызвать её в `sync-to-project.ps1`**

Заменить строку 112:

```powershell
$targetProject = Resolve-Directory -Path $ProjectPath -Name "Target project"
```

на:

```powershell
$targetProject = Resolve-Directory -Path $ProjectPath -Name "Target project"
Assert-CorporateLayer -ProjectRoot $targetProject
```

- [ ] **Шаг 5: Проверить негативный и позитивный случай**

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath "<SCRATCH>/no-corp-project"
```

Ожидается: отказ с текстом `Corporate agent layer is missing in target project
(no AGENTS.md)`, ненулевой код возврата, список файлов не печатается.

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath C:/Users/jarin/git/sollers/MBS
```

Ожидается: обычный dry-run со сводкой `Summary: Add=… Update=… Unchanged=…`.

- [ ] **Шаг 6: Повторить то же в `bootstrap-project.ps1`**

Добавить ту же функцию `Assert-CorporateLayer` (скрипты независимы, общего
модуля у них нет) и вызвать её сразу после строки 234:

```powershell
$targetProject = Resolve-Directory -Path $ProjectPath -Name "Target project"
Assert-CorporateLayer -ProjectRoot $targetProject
```

- [ ] **Шаг 7: Проверить bootstrap на обоих случаях**

```bash
powershell -ExecutionPolicy Bypass -File tools/bootstrap-project.ps1 -ProjectPath "<SCRATCH>/no-corp-project"
```

Ожидается: тот же отказ.

```bash
powershell -ExecutionPolicy Bypass -File tools/bootstrap-project.ps1 -Project MBS
```

Ожидается: обычный dry-run.

- [ ] **Шаг 8: Коммит**

```bash
git add tools/sync-to-project.ps1 tools/bootstrap-project.ps1
git commit -m "Личный слой: отказ при установке без корпоративного слоя"
```

---

### Задача 2: Переезд входной точки Claude Code

**Файлы:**
- Переместить: `template/project/.claude/CLAUDE.md` →
  `template/project/CLAUDE.local.md`
- Изменить: `tools/sync-to-project.ps1` (`$syncRoots`, строка 115)
- Изменить: `tools/bootstrap-project.ps1` (`$overwriteRoots`, строка 237)

**Интерфейсы:**
- Потребляет: `Assert-CorporateLayer` из Задачи 1.
- Производит: путь доставки `CLAUDE.local.md` в корне целевого проекта.

- [ ] **Шаг 1: Переместить файл с сохранением истории**

```bash
git mv template/project/.claude/CLAUDE.md template/project/CLAUDE.local.md
```

- [ ] **Шаг 2: Заменить шапку файла**

В `template/project/CLAUDE.local.md` заменить строки 1–11 (от `# <Project Name>`
до строки `` `CLAUDE.md`. `` включительно) на:

```markdown
# Личный AIDD-слой — входная точка Claude Code

## Назначение

Это входная точка личного AIDD-слоя поверх корпоративного agent layer MPL
Systems. Файл gitignored в рабочем проекте; его источник — шаблон
`1c-aidd-template`.

Личный слой — **надстройка**. Он не работает без корпоративного слоя и не
дублирует его: техническая процедура 1С/EDT живёт только в skills `mpl-*`, здесь
остаётся только AIDD-специфика.

Корпоративному слою принадлежат и личным слоем не изменяются:

- `AGENTS.md` в корне — корпоративная точка входа, читается Codex нативно;
- `.claude/CLAUDE.md` — корпоративный мост Claude Code (`@../AGENTS.md`);
- `.claude/rules/mpl/`, `.claude/skills/mpl-*`, `doc/ai/**` — корпоративные
  правила, skills и стандарты.

Файл должен оставаться коротким индексом и не дублировать подробные правила из
`.claude/rules/core`, `.claude/skills`, `.claude/agents`, project rules и
supporting docs.
```

- [ ] **Шаг 3: Дописать корпоративный слой в раздел «Слои конфигурации»**

После пункта `` - `docs`: supporting docs. `` добавить абзац:

```markdown
Корпоративный слой (`AGENTS.md`, `.claude/rules/mpl/`, `.claude/skills/mpl-*`,
`doc/ai/**`) загружается параллельно и независимо. Личные правила не отключают
корпоративные skills `mpl-*` и правила безопасности; при конфликте вынеси вопрос
пользователю.
```

- [ ] **Шаг 4: Дописать оговорку в раздел «Приоритет источников»**

После нумерованного списка (после пункта `7. Supporting docs из
.claude/docs/*.md.`) добавить:

```markdown
Корпоративные правила безопасности и skills `mpl-*` не отключаются ни одним
пунктом этого списка. Если личное правило противоречит корпоративному
инварианту, вынеси вопрос пользователю.
```

- [ ] **Шаг 5: Заменить путь в `$syncRoots`**

В `tools/sync-to-project.ps1` заменить строку 115:

```powershell
    ".claude/CLAUDE.md",
```

на:

```powershell
    "CLAUDE.local.md",
```

- [ ] **Шаг 6: Заменить путь в `$overwriteRoots`**

В `tools/bootstrap-project.ps1` заменить строку 237 тем же образом.

- [ ] **Шаг 7: Проверить dry-run по MBS**

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath C:/Users/jarin/git/sollers/MBS
```

Ожидается: в выводе присутствует строка со статусом для `CLAUDE.local.md` и
**отсутствует** любая строка с `.claude/CLAUDE.md`. Это ключевая проверка всей
задачи: корпоративный мост вышел из зоны досягаемости скрипта.

- [ ] **Шаг 8: Коммит**

```bash
git add template/project/CLAUDE.local.md tools/sync-to-project.ps1 tools/bootstrap-project.ps1
git commit -m "Личный слой: точка входа Claude переехала в CLAUDE.local.md"
```

---

### Задача 3: Переезд входной точки Codex

**Файлы:**
- Переместить: `template/project/AGENTS.md` →
  `template/project/.agents/local/instructions.md`
- Изменить: `tools/sync-to-project.ps1` (`$syncRoots`)
- Изменить: `tools/bootstrap-project.ps1` (`$overwriteRoots`,
  `$createIfMissingRoots`)

**Интерфейсы:**
- Производит: путь доставки `.agents/local/instructions.md`. Корпоративный
  `AGENTS.md` читает этот файл явно — см. раздел «Личное расширение»
  корпоративного `AGENTS.md`.

- [ ] **Шаг 1: Прочитать файл целиком**

Прочитать `template/project/AGENTS.md` полностью: дальше меняется только шапка,
остальное сохраняется дословно, и надо знать, что именно сохраняется.

- [ ] **Шаг 2: Переместить файл с сохранением истории**

```bash
mkdir -p template/project/.agents/local
git mv template/project/AGENTS.md template/project/.agents/local/instructions.md
```

- [ ] **Шаг 3: Заменить шапку файла**

Заменить строки 1–18 (от `# AGENTS.md` до строки `- aidd/docs/* — рабочие
артефакты тикетов.` включительно) на:

```markdown
# Личный AIDD-слой — инструкции Codex

Этот файл — личная надстройка над корпоративным agent layer MPL Systems.
Корпоративный `AGENTS.md` в корне репозитория читает его явно; сам `AGENTS.md`
принадлежит корпоративному слою и личным слоем не изменяется.

Надстройка не дублирует корпоративный слой: техническая процедура 1С/EDT живёт
только в skills `mpl-*`, здесь остаётся AIDD-специфика — workflow, артефакты
тикета и маршрутизация сценариев.

Источники истины личного слоя:

- `CLAUDE.local.md` — входная точка личного слоя (общая с Claude Code);
- `.claude/docs/onboarding-project.md` — сценарий обследования и настройки
  project-specific правил;
- `.claude/rules/core/*.md` — переносимые правила;
- `.claude/rules/project/*.md` — специфика текущего проекта;
- `.claude/rules/paths/*.md` — правила для отдельных зон дерева;
- `.mcp.json` — project-local выбор и подключение единственного EDT MCP;
- `aidd/docs/*` — рабочие артефакты тикетов.
```

- [ ] **Шаг 4: Пройти по остатку файла**

В сохранённой части заменить каждое упоминание `.claude/CLAUDE.md` на
`CLAUDE.local.md`. Утверждений о том, что этот файл является `AGENTS.md`
проекта, остаться не должно. Другие правки не вносить.

- [ ] **Шаг 5: Добавить путь в `$syncRoots`**

В `tools/sync-to-project.ps1` добавить вторым элементом, сразу после
`"CLAUDE.local.md",`:

```powershell
    ".agents/local/instructions.md",
```

- [ ] **Шаг 6: Обновить оба списка bootstrap**

В `tools/bootstrap-project.ps1` добавить `".agents/local/instructions.md",` в
`$overwriteRoots` сразу после `"CLAUDE.local.md",`, и удалить строку
`"AGENTS.md",` из `$createIfMissingRoots`.

- [ ] **Шаг 7: Проверить dry-run по MBS**

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath C:/Users/jarin/git/sollers/MBS
```

Ожидается: есть строка для `.agents/local/instructions.md`; строк с `AGENTS.md`
и `.claude/CLAUDE.md` нет.

```bash
powershell -ExecutionPolicy Bypass -File tools/bootstrap-project.ps1 -Project MBS
```

Ожидается: то же самое, и в списке нет `AGENTS.md` со статусом создания.

- [ ] **Шаг 8: Коммит**

```bash
git add template/project/.agents/local/instructions.md tools/sync-to-project.ps1 tools/bootstrap-project.ps1
git commit -m "Личный слой: точка входа Codex переехала в .agents/local"
```

---

### Задача 4: README шаблона

**Файлы:**
- Изменить: `README.md`

- [ ] **Шаг 1: Добавить раздел о предпосылке**

После вводного абзаца (после строки 6) вставить:

```markdown
## Предпосылка: надстройка над корпоративным слоем

Начиная с 2026-08-10 этот шаблон — **надстройка** над корпоративным agent layer
MPL Systems (`AGENTS.md`, `.agents/skills/mpl-*`, `doc/ai/**`), который
поставляется через `EDT-project-template`. Самостоятельно личный слой не
работает: он ссылается на skills `mpl-*`.

`tools/sync-to-project.ps1` и `tools/bootstrap-project.ps1` отказываются
устанавливать слой в проект без корпоративного основания.

Имена `AGENTS.md` и `.claude/CLAUDE.md` принадлежат корпоративному слою. Личные
точки входа — корневой `CLAUDE.local.md` и `.agents/local/instructions.md`.
```

- [ ] **Шаг 2: Применить точечные замены**

| Строка (до правки) | Что сделать |
|---|---|
| 35, блок структуры: `      CLAUDE.md` | убрать из `.claude/`; добавить `CLAUDE.local.md` и `.agents/local/instructions.md` на уровень `template/project/` |
| 95: `` `.claude/CLAUDE.md`, `.claude/settings.json`, `.claude/agents`, `` | заменить `.claude/CLAUDE.md` на `CLAUDE.local.md` и `.agents/local/instructions.md` |
| 101: `- создает отсутствующий локальный AGENTS.md;` | удалить пункт |
| 109: `- не добавляет .claude/, aidd/ или AGENTS.md в Git ignore/exclude;` | заменить `AGENTS.md` на `CLAUDE.local.md` |
| 122–123: `Для Codex входом является локальный AGENTS.md` | заменить на `.agents/local/instructions.md` |
| 143: `` - `.claude/CLAUDE.md` как project entry point; `` | заменить на `` - `CLAUDE.local.md` как личная точка входа Claude Code; `` |
| 144: `` - `AGENTS.md` как локальная входная инструкция Codex; `` | заменить на `` - `.agents/local/instructions.md` как личная инструкция Codex; `` |
| 195: `` - `.claude/CLAUDE.md`; `` | заменить на `` - `CLAUDE.local.md`; `` |
| 228: `` - `.claude/CLAUDE.md`; `` | удалить пункт: путь больше не принадлежит шаблону |
| 357: `` - `.claude/CLAUDE.md`: нейтральный project entry point… `` | переименовать в `CLAUDE.local.md` |
| 373: `` - `AGENTS.md`: нейтральный Codex entry point… `` | переименовать в `.agents/local/instructions.md` |

- [ ] **Шаг 3: Переписать абзац о корневом `CLAUDE.md`**

Заменить абзац на строках 256–261 (начинается «В конечных проектах не следует
добавлять корневой `CLAUDE.md`…») на:

```markdown
Имя `.claude/CLAUDE.md` в конечном проекте занято корпоративным мостом
(`@../AGENTS.md`) и шаблоном не поставляется. Личная точка входа Claude Code —
корневой gitignored `CLAUDE.local.md`; корневой `CLAUDE.md` не создаём, чтобы не
плодить конкурирующие источники project memory. Проектная специфика остаётся в
`.claude/rules/project` и `.claude/rules/paths`.
```

- [ ] **Шаг 4: Проверить, что не осталось устаревших утверждений**

Поиск по `README.md` строки `.claude/CLAUDE.md`. Допустимые оставшиеся
вхождения — только те, где путь назван как принадлежащий **корпоративному**
слою. Любое место, где он описан как поставляемый шаблоном project entry point,
— незакрытая правка.

- [ ] **Шаг 5: Коммит**

```bash
git add README.md
git commit -m "Личный слой: README описывает шаблон как надстройку"
```

---

### Задача 5: Применение в MBS и верификация

**Файлы:**
- Изменить (в MBS, вне Git): `CLAUDE.local.md`,
  `.agents/local/instructions.md`

- [ ] **Шаг 1: Сверить существующие файлы MBS с новыми шаблонными**

В MBS уже есть `CLAUDE.local.md` и `.agents/local/instructions.md` — они были
созданы вручную при установке корпоративного слоя 2026-08-08. Прочитать обе
пары и выписать, что есть в версии MBS и чего нет в шаблонной.

Если в MBS-версии найдено содержание, отсутствующее в шаблоне и не являющееся
проектной спецификой MBS, — перенести его в шаблон и повторить Задачу 2 или 3
для этого фрагмента до применения. Проектная специфика MBS в эти файлы попадать
не должна: её место в `.claude/rules/project/*`.

- [ ] **Шаг 2: Dry-run**

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath C:/Users/jarin/git/sollers/MBS
```

Ожидается: `Update CLAUDE.local.md`, `Update .agents/local/instructions.md`,
никаких строк с `.claude/CLAUDE.md` и `AGENTS.md`.

- [ ] **Шаг 3: Применить**

```bash
powershell -ExecutionPolicy Bypass -File tools/sync-to-project.ps1 -ProjectPath C:/Users/jarin/git/sollers/MBS -Apply
```

- [ ] **Шаг 4: Проверить, что корпоративный слой цел**

Прочитать `C:/Users/jarin/git/sollers/MBS/.claude/CLAUDE.md`. Ожидается: файл
содержит строку `@../AGENTS.md` — корпоративный мост не тронут.

```bash
git -C /c/Users/jarin/git/sollers/MBS status --short
```

Ожидается: `.claude/CLAUDE.md` и `AGENTS.md` в изменённых не значатся.
`.claude/` и `.agents/local/` gitignored, поэтому личные файлы в выводе тоже не
появятся — это ожидаемо.

- [ ] **Шаг 5: Проверить загрузку слоёв в новой сессии**

Открыть новую сессию Claude Code в MBS и убедиться, что в контексте
присутствуют одновременно: корпоративный `AGENTS.md` (через мост) и личная
входная точка `CLAUDE.local.md`. Это единственная проверка, которую нельзя
сделать скриптом.

- [ ] **Шаг 6: Обновить roadmap**

В `docs/roadmap-team-agent-layer.md` добавить пункт о закрытии И0 и о том, что
Б3 стал инкрементом И4 подпроекта консолидации.

```bash
git add docs/roadmap-team-agent-layer.md
git commit -m "Roadmap: И0 закрыт, консолидация личного слоя запущена"
```

## Проверка плана против спеки

- Дефект «синхронизация затирает корпоративный мост» — Задачи 1, 2, 5.
- Дефект «тот же список в bootstrap» — Задачи 1, 2, 3.
- Codex-близнец переезда — Задача 3.
- Проверка предусловия — Задача 1.
- Правка README — Задача 4.
- Критерий «синхронизация не может затронуть `.claude/CLAUDE.md`» — Задача 2,
  шаг 7 и Задача 5, шаг 4.
- Критерий «отказ для проекта без корпоративного слоя» — Задача 1, шаги 5 и 7.

Вне И0 остаются: удаление дублирующих skills (И1–И3), роль исполнителя (И4),
обёртки (И5), правила `rules/core` (И6). Ссылки на личные skills в
`CLAUDE.local.md` в этом инкременте не трогаются — они станут висячими только
после удаления самих skills и чинятся в том же инкременте, где удаляются.
