# План: переезд дома разработки agent layer в шаблон и wiki

> **Переехало.** Актуальная версия — в wiki шаблона, раздел
> `agent-layer/dev`. Здесь файл заморожен и не обновляется.

> **Для исполнителя-агента:** ОБЯЗАТЕЛЬНЫЙ СУБ-SKILL — `superpowers:subagent-driven-development`
> (рекомендуется) или `superpowers:executing-plans`. Шаги отмечаются чекбоксами `- [ ]`.

**Цель:** перенести дом разработки корпоративного agent layer `mpl-*` из проекта
MBS в репозиторий `EDT-project-template` и его wiki так, чтобы всё знание о слое
оказалось в git и не разъезжалось по проектам-потребителям.

**Архитектура:** слой остаётся в шаблоне и не меняется. Мета-знание (продуктовая
дока, журнал, спеки, планы, roadmap) переезжает в отдельный git-репозиторий
`EDT-project-template.wiki.git`, который не доставляется merge'ем в проекты.
Рабочим каталогом сессий становится чекаут шаблона с развёрнутым поверх личным
AIDD-слоем. Auto-память Claude Code сокращается до указателя на журнал.

**Инструменты:** git, GitLab wiki (отдельный репозиторий `*.wiki.git`),
PowerShell (`bootstrap-project.ps1`), Python (валидатор слоя), bash
(`mpl-render-claude-layer.sh`, `commit-block.sh`).

**Спека:** `docs/specs/2026-08-13-agent-layer-home-migration-design.md`

## Глобальные ограничения

- **Язык.** Все создаваемые документы — на русском.
- **Коммиты только явными путями.** Прямые `git add` и `git commit` блокируются
  hook'ом личного слоя. В `1c-aidd-template` использовать
  `bash template/project/.claude/scripts/commit-block.sh "<subject>" --add-path <путь> --body-line "<строка>"`.
  В wiki и шаблоне — тот же helper по его фактическому пути в этом чекауте.
- **Push — только по явному подтверждению человека**, отдельным шагом, с явным
  `git push origin <ветка>`. Голый `git push` запрещён.
- **Корпоративный слой в этой задаче не меняется.** `AGENTS.md`, `doc/ai/**`,
  `.agents/skills/mpl-*`, `.claude/skills/mpl-*`, `tools/ai/**` остаются как есть.
  Если по ходу выясняется, что правка нужна, — это отдельное решение человека,
  а не часть переезда.
- **Форма страниц wiki** повторяет существующую: frontmatter с единственным
  ключом `title:`, внутренние ссылки вида `/раздел/Страница` или
  `[Текст](Имя-Страницы)`, пробелы в именах файлов заменяются дефисами.
- **Порядок записи.** Сначала коммит слоя, затем запись в журнал со ссылкой на
  SHA. Обратный порядок даёт ссылку в пустоту.
- **Ключи тикетов и имена проектов в wiki допустимы.** Запрет на них действует
  только внутри корпоративного слоя и держится валидатором.

## Карта файлов

| Репозиторий | Путь | Что происходит |
|---|---|---|
| `1c-aidd-template` | `config/projects.local.json` | добавляется запись `EDT-project-template` |
| `1c-aidd-template` | `docs/**` (13 файлов) | копируются в wiki, на месте получают шапку «заморожено» |
| `EDT-project-template` | `.git/info/exclude` | локальные исключения для файлов, которые создаёт личный слой |
| `EDT-project-template` | рабочее дерево | появляется gitignored личный слой |
| `EDT-project-template.wiki` | `agent-layer/**` | создаётся весь раздел |
| `EDT-project-template.wiki` | `home.md` | добавляется одна ссылка |
| auto-память MBS | `team-agent-layer-pilot.md`, `team-ai-layer-project.md`, `MEMORY.md` | заменяются указателем |
| auto-память шаблона | новый каталог | создаётся указатель |

Постоянные пути:

- шаблон — `C:/Users/jarin/git/sollers/EDT-project-template`
- клон wiki — `C:/Users/jarin/git/sollers/EDT-project-template.wiki`
- личный репо — `C:/Users/jarin/git/my-projects/1c-aidd-template`

---

### Задача 1: Привести незапушенное в порядок (Б0)

Переезжать поверх незакоммиченного и незапушенного нельзя: потеря будет молчаливой.

**Файлы:**
- Коммит: `docs/specs/2026-08-13-template-baseline-onboarding-design.md` (untracked)
- Коммит: `docs/plans/2026-08-13-agent-layer-home-migration.md` (этот план, untracked)

- [ ] **Шаг 1: Снять фактическое состояние обоих репозиториев**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && git status --short --branch
cd "C:/Users/jarin/git/sollers/EDT-project-template" && git status --short --branch
```

Ожидание: личный репо `ahead` от `origin/main` и две untracked спеки/план;
шаблон `ahead 8` от `origin/feature/team-ai-tools-v2`, рабочее дерево чистое.
Если шаблон не чист — остановиться и показать человеку, ничего не коммитить.

- [ ] **Шаг 2: Закоммитить untracked спеку baseline-онбординга**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && \
bash template/project/.claude/scripts/commit-block.sh \
  "Спека: baseline шаблона и переписанный онбординг" \
  --add-path docs/specs/2026-08-13-template-baseline-onboarding-design.md \
  --body-line "Спека была написана 2026-08-13 и осталась вне индекса."
```

- [ ] **Шаг 3: Закоммитить этот план**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && \
bash template/project/.claude/scripts/commit-block.sh \
  "План: переезд дома разработки agent layer" \
  --add-path docs/plans/2026-08-13-agent-layer-home-migration.md \
  --body-line "План к спеке 2026-08-13-agent-layer-home-migration-design.md."
```

- [ ] **Шаг 4: Проверить, что рабочие деревья чисты**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && git status --short
```

Ожидание: пустой вывод.

- [ ] **Шаг 5: Запросить у человека подтверждение на push и выполнить его**

Push — внешнее действие. Спросить явно, затем:

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template" && git push origin feature/team-ai-tools-v2
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && git push origin main
```

Ветка называется явно: голый `git push` в репозиториях этого набора уже
приводил к отправке не в ту ветку.

- [ ] **Шаг 6: Подтвердить синхронизацию**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template" && git status --short --branch
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && git status --short --branch
```

Ожидание: ни `ahead`, ни `behind` в обеих строках `##`.

---

### Задача 2: Развернуть личный слой в чекаут шаблона (Б1)

**Интерфейсы:**
- Использует: `tools/bootstrap-project.ps1 -Project <имя> [-Apply]` из личного репо.
  Скрипт **не** правит игнор-файлы — исключения делаются вручную в этой же задаче.
- Даёт: рабочий каталог шаблона, пригодный для сессий, с чистым `git status`.

**Файлы:**
- Изменить: `C:/Users/jarin/git/my-projects/1c-aidd-template/config/projects.local.json`
- Изменить: `C:/Users/jarin/git/sollers/EDT-project-template/.git/info/exclude`

- [ ] **Шаг 1: Добавить шаблон в локальный список проектов**

Файл gitignored и machine-specific, коммита не требует. Целевое содержимое:

```json
{
  "projects": [
    {
      "name": "MBS",
      "path": "C:/Users/jarin/git/sollers/MBS",
      "enabled": true
    },
    {
      "name": "EDT-project-template",
      "path": "C:/Users/jarin/git/sollers/EDT-project-template",
      "enabled": true
    }
  ]
}
```

- [ ] **Шаг 2: Прогнать bootstrap без применения и прочитать список операций**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && \
powershell -NoProfile -File tools/bootstrap-project.ps1 -Project EDT-project-template
```

Вывод — это вход для шага 4. Выписать все пути с операцией `Add`, которые
**не** попадают под `.gitignore` шаблона. Под игнор уже попадают:
`.claude/*` кроме `mpl`-разрешений, `/CLAUDE.local.md`, `.agents/local/`,
`.agents/state/`, `.mcp.json`. Заведомо **не** попадают каталоги вида `aidd/**`.

Если dry-run падает на `Assert-CorporateLayer` — значит выбран не тот путь;
остановиться и показать вывод человеку.

- [ ] **Шаг 3: Применить bootstrap**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && \
powershell -NoProfile -File tools/bootstrap-project.ps1 -Project EDT-project-template -Apply
```

- [ ] **Шаг 4: Закрыть неигнорируемые пути локальным исключением**

Правится `.git/info/exclude` чекаута шаблона — локальный файл, не отслеживается
и не доставляется в проекты. Отслеживаемый `.gitignore` шаблона **не трогать**:
это корпоративный файл, а причина исключения здесь личная.

Добавить в конец `C:/Users/jarin/git/sollers/EDT-project-template/.git/info/exclude`
блок с заголовком-комментарием и по строке на каждый путь из шага 2. Как минимум:

```
# Личный AIDD-слой в чекауте шаблона: рабочее место сопровождающего,
# в корпоративный .gitignore не выносится.
/aidd/
```

- [ ] **Шаг 5: Проверить, что шаблон по-прежнему чист**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template" && git status --short
```

Ожидание: **пустой вывод**. Любая строка означает, что личный файл виден Git —
дописать путь в `.git/info/exclude` и повторить. Не коммитить ничего.

- [ ] **Шаг 6: Проверить, что личный слой не сломал корпоративный**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template" && python tools/ai/mpl-validate-agent-layer.py
cd "C:/Users/jarin/git/sollers/EDT-project-template" && bash tools/ai/mpl-render-claude-layer.sh --check
```

Ожидание: валидатор без ошибок, render `--check` без расхождений. Это заодно
регрессионная проверка того, что развёрнутый рядом личный слой не попадает под
корпоративные сканирования.

Если `python` не находится, использовать `python3`.

---

### Задача 3: Постоянный клон wiki и каркас раздела (Б2)

**Интерфейсы:**
- Даёт: путь `C:/Users/jarin/git/sollers/EDT-project-template.wiki` и две
  страницы-навигации, на которые ссылаются все последующие задачи.

**Файлы:**
- Создать: `EDT-project-template.wiki/agent-layer/home.md`
- Создать: `EDT-project-template.wiki/agent-layer/dev/home.md`

- [ ] **Шаг 1: Клонировать wiki в постоянное место**

```bash
git clone "https://gitlab.dev-portal.ru/mpl-systems/EDT-project-template.wiki.git" "C:/Users/jarin/git/sollers/EDT-project-template.wiki"
```

Клон намеренно кладётся **соседом**, а не внутрь чекаута шаблона: вложенный
клон потребовал бы строки в отслеживаемом `.gitignore` шаблона.

- [ ] **Шаг 2: Создать заглушку `agent-layer/home.md`**

Полное содержимое страницы пишется в задаче 6; здесь — минимальный каркас,
чтобы навигация и ссылки существовали с самого начала.

```markdown
---
title: Корпоративный agent layer MPL Systems
---

# Корпоративный agent layer MPL Systems

Общая AI-обвязка для проектов 1С/EDT: работает с Claude Code и Codex,
доставляется через шаблон проекта.

Раздел наполняется. Материал сопровождающего слоя — в
[dev](/agent-layer/dev/home).
```

- [ ] **Шаг 3: Создать `agent-layer/dev/home.md`**

```markdown
---
title: agent layer — материалы сопровождающего
---

# agent layer — материалы сопровождающего

Рабочие материалы разработки слоя. Команде для использования слоя они не нужны —
точка входа находится в [agent-layer](/agent-layer/home).

- [Журнал](/agent-layer/dev/Журнал) — решения, находки и уроки по датам
- [Roadmap](/agent-layer/dev/Roadmap) — бэклог и статус пунктов
- `specs/` — спеки дизайн-пунктов
- `plans/` — планы реализации
- `reviews/` — отчёты ревизий

## Правила сопровождения

- Дом слоя — репозиторий `EDT-project-template`, ветка слоя. Мета-знание —
  этот раздел wiki. Рабочий каталог сессии — чекаут шаблона с развёрнутым
  поверх личным AIDD-слоем.
- Изменение слоя = коммит в шаблоне, **затем** запись в журнале со ссылкой на
  SHA. Обратный порядок даёт ссылку в пустоту: репозитории разные, атомарности
  между ними нет.
- Спека или план нового дизайн-пункта пишется сразу сюда, а не в личный
  репозиторий.
- Если изменение меняет поверхность слоя — новый skill, новая роль, порядок
  установки — в том же заходе правится соответствующая страница
  `agent-layer/*`.
- Wiki не покрыта валидатором и CI: битые ссылки между страницами не поймает
  никто. Проверяются вручную при правке навигации.
- Ключи тикетов и имена проектов здесь допустимы. Запрет на них действует
  только внутри корпоративного слоя и держится валидатором.
```

Правила сопровождения записываются здесь, а не только в плане: план — одноразовый
документ, а правила должны пережить его.

- [ ] **Шаг 4: Закоммитить каркас**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && \
bash "C:/Users/jarin/git/my-projects/1c-aidd-template/template/project/.claude/scripts/commit-block.sh" \
  "agent layer: каркас раздела wiki" \
  --add-path agent-layer/home.md \
  --add-path agent-layer/dev/home.md \
  --body-line "Раздел разделён на продуктовую доку для команды и материалы" \
  --body-line "сопровождающего: у них разная аудитория."
```

Helper берёт репозиторий из `git rev-parse`, поэтому работает из любого чекаута.

- [ ] **Шаг 5: Проверить и запросить push**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && git status --short --branch
```

После явного подтверждения человека:

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && git push origin main
```

---

### Задача 4: Перенос спек, планов, ревизии и roadmap (Б3)

**Интерфейсы:**
- Использует: `agent-layer/dev/home.md` из задачи 3.
- Даёт: `agent-layer/dev/Roadmap.md`, наполненные `specs/`, `plans/`, `reviews/`.

**Файлы (13 штук, источник → приёмник):**

| Источник в `1c-aidd-template/docs/` | Приёмник в `wiki/agent-layer/dev/` |
|---|---|
| `roadmap-team-agent-layer.md` | `Roadmap.md` |
| `specs/2026-08-08-hermes-agent-layer-review-design.md` | `specs/` тем же именем |
| `specs/2026-08-08-project-path-rules-design.md` | `specs/` тем же именем |
| `specs/2026-08-10-personal-layer-consolidation-design.md` | `specs/` тем же именем |
| `specs/2026-08-12-implement-pipeline-design.md` | `specs/` тем же именем |
| `specs/2026-08-12-corporate-mr-review-design.md` | `specs/` тем же именем |
| `specs/2026-08-13-template-baseline-onboarding-design.md` | `specs/` тем же именем |
| `specs/2026-08-13-agent-layer-home-migration-design.md` | `specs/` тем же именем |
| `plans/2026-08-08-hermes-agent-layer-review.md` | `plans/` тем же именем |
| `plans/2026-08-08-project-path-rules.md` | `plans/` тем же именем |
| `plans/2026-08-10-personal-layer-i0-superstructure.md` | `plans/` тем же именем |
| `plans/2026-08-13-agent-layer-home-migration.md` | `plans/` тем же именем |
| `reviews/2026-08-08-hermes-agent-layer-review.md` | `reviews/` тем же именем |

- [ ] **Шаг 1: Скопировать файлы в клон wiki**

Копирование, а не перемещение: история личного репозитория остаётся целой.
Имена файлов сохраняются — они уже без пробелов, слаг wiki получится читаемым.

- [ ] **Шаг 2: Сверить, что перенеслось ровно 13 файлов**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && git status --short --untracked-files=all
```

Ожидание: ровно 13 строк `??` и ничего лишнего. Флаг `--untracked-files=all`
обязателен: без него git схлопывает новый каталог в одну строку и пересчитать
файлы будет нельзя.

- [ ] **Шаг 3: Закоммитить перенос в wiki**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && \
bash "C:/Users/jarin/git/my-projects/1c-aidd-template/template/project/.claude/scripts/commit-block.sh" \
  "agent layer: спеки, планы и roadmap переехали в wiki" \
  --add-path agent-layer/dev/Roadmap.md \
  --add-path agent-layer/dev/specs \
  --add-path agent-layer/dev/plans \
  --add-path agent-layer/dev/reviews \
  --body-line "Источник — личный репозиторий 1c-aidd-template; там файлы" \
  --body-line "остаются замороженными, точка истины теперь одна."
```

- [ ] **Шаг 4: Поставить шапку «заморожено» на оригиналы**

В каждый из 13 файлов личного репо первой строкой после заголовка добавить:

```markdown
> **Переехало.** Актуальная версия — в wiki шаблона, раздел
> `agent-layer/dev`. Здесь файл заморожен и не обновляется.
```

- [ ] **Шаг 5: Закоммитить шапки в личном репо**

```bash
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && \
bash template/project/.claude/scripts/commit-block.sh \
  "Документы разработки слоя переехали в wiki шаблона" \
  --add-path docs \
  --body-line "Файлы не удаляются: история личного репозитория остаётся целой." \
  --body-line "Дальнейшие правки идут только в wiki."
```

- [ ] **Шаг 6: Push обоих репозиториев после подтверждения**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && git push origin main
cd "C:/Users/jarin/git/my-projects/1c-aidd-template" && git push origin main
```

---

### Задача 5: Журнал мета-проекта и сокращение памяти (Б4)

Самая ценная и самая хрупкая часть переезда: сейчас это знание существует в
единственном экземпляре вне git.

**Интерфейсы:**
- Даёт: `agent-layer/dev/Журнал.md`, на который ссылаются обе записи памяти.

**Файлы:**
- Создать: `EDT-project-template.wiki/agent-layer/dev/Журнал.md`
- Источник: `C:/Users/jarin/.claude/projects/c--Users-jarin-git-sollers-MBS/memory/team-agent-layer-pilot.md`
- Источник: `C:/Users/jarin/.claude/projects/c--Users-jarin-git-sollers-MBS/memory/team-ai-layer-project.md`
- Заменить: те же два файла + `MEMORY.md` в памяти MBS
- Создать: `C:/Users/jarin/.claude/projects/c--Users-jarin-git-sollers-EDT-project-template/memory/agent-layer-journal.md` и `MEMORY.md`

- [ ] **Шаг 1: Прочитать оба файла памяти целиком**

Никакой выборочности: перенос должен быть полным, потери здесь необратимы.

- [ ] **Шаг 2: Собрать `Журнал.md`**

Не дамп, а структурированный документ. Обязательная структура:

```markdown
---
title: agent layer — журнал мета-проекта
---

# Журнал мета-проекта

## Текущее состояние

<состояние на сегодня: где ветки, что запушено, что следующее>

## Принятые решения

<решения владельца с датами и причиной, по которой альтернатива отвергнута>

## Закрытые инкременты

<И0..И6, Б1..Б7 — что сделано, каким коммитом, чем проверено>

## Ловушки и уроки

<ловушки среды и инструментов, уроки процесса>

## История раскаток

<MBS, hermy-PROSYS-Avtolid — состояние и особенности каждой>
```

Требования к содержанию: сохранить **все** SHA коммитов, все решения владельца
вместе с причиной отказа от альтернатив и все ловушки среды. Устаревшие
утверждения не выбрасывать молча, а помечать: запись «обе ветки запушены
2026-08-13» на момент переезда уже неверна, и именно такие расхождения дороже
всего.

- [ ] **Шаг 3: Закоммитить и запушить журнал**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && \
bash "C:/Users/jarin/git/my-projects/1c-aidd-template/template/project/.claude/scripts/commit-block.sh" \
  "agent layer: журнал мета-проекта переехал в wiki" \
  --add-path agent-layer/dev/Журнал.md \
  --body-line "Источник — auto-память Claude Code для пути MBS: единственный" \
  --body-line "экземпляр вне git."
```

После подтверждения — `git push origin main`.

- [ ] **Шаг 4: Завести указатель в памяти шаблона**

Создать `C:/Users/jarin/.claude/projects/c--Users-jarin-git-sollers-EDT-project-template/memory/agent-layer-journal.md`:

```markdown
---
name: agent-layer-journal
description: "Журнал мета-проекта «корпоративный agent layer» живёт в wiki шаблона; здесь только указатель"
metadata:
  type: project
---

Полное состояние мета-проекта — в wiki репозитория, страница
`agent-layer/dev/Журнал`. Постоянный клон:
`C:/Users/jarin/git/sollers/EDT-project-template.wiki`.

Читать журнал в начале любой задачи по слою: здесь его содержимого нет
намеренно, чтобы не было двух расходящихся копий.

Рабочий каталог для работы над слоем — этот репозиторий; поверх него развёрнут
личный AIDD-слой из `1c-aidd-template`.
```

Добавить строку в `MEMORY.md` того же каталога.

- [ ] **Шаг 5: Заменить память MBS на указатель**

Удалить `team-agent-layer-pilot.md` и `team-ai-layer-project.md`, создать вместо
них `agent-layer-moved.md`:

```markdown
---
name: agent-layer-moved
description: "Работа по корпоративному agent layer переехала в репозиторий шаблона и его wiki; из MBS ей больше не управляют"
metadata:
  type: project
---

Разработка слоя `mpl-*` больше не ведётся из MBS. Дом — репозиторий
`EDT-project-template`, мета-знание — его wiki, раздел `agent-layer`.

MBS остаётся площадкой потребления слоя и пилотов. Прежние записи
`team-agent-layer-pilot` и `team-ai-layer-project` удалены: они начали бы
расходиться с журналом с первого же дня.
```

Обновить `MEMORY.md` памяти MBS: убрать две строки, добавить одну.

- [ ] **Шаг 6: Проверить, что содержимое не потеряно**

Сверить журнал с исходными файлами: каждый SHA, каждое решение владельца и
каждая ловушка должны иметь соответствие. Только после этой сверки удалять
исходные записи памяти.

---

### Задача 6: Продуктовая дока — вход и установка (Б5, часть 1)

**Интерфейсы:**
- Использует: `doc/ai/README.md` и `doc/ai/template-baseline.md` шаблона как
  фактический источник; `AGENTS.md` как перечень стандартов.
- Даёт: `agent-layer/home.md` в полном виде и `agent-layer/Установка.md`.

**Файлы:**
- Изменить: `EDT-project-template.wiki/agent-layer/home.md`
- Создать: `EDT-project-template.wiki/agent-layer/Установка.md`

- [ ] **Шаг 1: Прочитать источники**

`doc/ai/README.md`, `doc/ai/template-baseline.md`, `AGENTS.md` в чекауте
шаблона. Писать страницы по фактическому состоянию слоя, а не по журналу:
журнал — рассказ о прошлом, дока — утверждение о настоящем.

- [ ] **Шаг 2: Написать `agent-layer/home.md`**

Обязательные разделы: что это и какую задачу решает; три слоя
(корпоративный → проектный → личный) и что каждый может и не может; где лежит
источник истины (репозиторий, ветка, каталоги `.agents/skills`, `doc/ai`,
`tools/ai`); чем Claude Code отличается от Codex в этой обвязке; ссылки на
`Установка`, `Каталог-skills`, `EDT-MCP`, `Обратная-связь` и одна строка на
`dev/home` с пометкой «материалы сопровождающего».

- [ ] **Шаг 3: Написать `agent-layer/Установка.md`**

Два сценария раздельно: чистый проект и проект с уже существующим личным
`.claude/`. Во втором явно назвать коллизию имён, из-за которой личные точки
входа переехали на `CLAUDE.local.md` и `.agents/local/instructions.md`.
Обязательно: выборочный блок `.gitignore`, команды проверки
(`mpl-validate-agent-layer.py`, `mpl-render-claude-layer.sh --check`) и
известная ловушка `core.filemode` на `tools/ai/*.sh`.

- [ ] **Шаг 4: Закоммитить**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && \
bash "C:/Users/jarin/git/my-projects/1c-aidd-template/template/project/.claude/scripts/commit-block.sh" \
  "agent layer: точка входа и установка" \
  --add-path agent-layer/home.md \
  --add-path agent-layer/Установка.md \
  --body-line "До этого описание слоя лежало внутри самого слоя и было доступно" \
  --body-line "только тому, кто слой уже получил."
```

---

### Задача 7: Продуктовая дока — каталог, MCP, обратная связь (Б5, часть 2)

**Файлы:**
- Создать: `EDT-project-template.wiki/agent-layer/Каталог-skills.md`
- Создать: `EDT-project-template.wiki/agent-layer/EDT-MCP.md`
- Создать: `EDT-project-template.wiki/agent-layer/Обратная-связь.md`

- [ ] **Шаг 1: Собрать фактический перечень skills и ролей**

Источник — каталоги `.agents/skills/mpl-*` и `.agents/roles/mpl-*` шаблона плюс
таблица маршрутизации в `AGENTS.md`. Перечень брать из файловой системы, а не
из памяти: он менялся (`mpl-address-review` → `mpl-fix-review`).

- [ ] **Шаг 2: Написать `Каталог-skills.md`**

Таблица «когда задача… → используй skill» с одной строкой на skill, плюс
отдельная короткая таблица ролей с указанием, что роли — механизм Claude Code,
а у Codex роль работает как документ-контракт.

- [ ] **Шаг 3: Написать `EDT-MCP.md`**

Три сервера (`edt-companion-mcp`, `edt-mcp`, `1c-rsv`), принцип
discovery-first и решение владельца: сервер каждый настраивает себе сам,
`.mcp.json` в Git не отслеживается, один сервер на команду не стандартизируется.
Обязательно назвать предусловие «EDT запущен, проект импортирован» — оно общее
для всех трёх серверов.

- [ ] **Шаг 4: Написать `Обратная-связь.md`**

Куда сообщать о проблеме слоя, что прикладывать (версия плагина/EDT, фактические
аргументы вызова, evidence, воспроизводимость), и правило: внешнюю заявку в
трекер инструмента создаёт человек, а не агент.

- [ ] **Шаг 5: Закоммитить**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && \
bash "C:/Users/jarin/git/my-projects/1c-aidd-template/template/project/.claude/scripts/commit-block.sh" \
  "agent layer: каталог skills, EDT MCP и обратная связь" \
  --add-path agent-layer/Каталог-skills.md \
  --add-path agent-layer/EDT-MCP.md \
  --add-path agent-layer/Обратная-связь.md \
  --body-line "Перечень skills и ролей собран из каталогов слоя, а не по памяти."
```

---

### Задача 8: Ссылка из корневой навигации wiki (Б6)

**Файлы:**
- Изменить: `EDT-project-template.wiki/home.md`

- [ ] **Шаг 1: Добавить раздел в корневой `home.md`**

После блока `## Инструменты` добавить:

```markdown
## AI-обвязка
* [Корпоративный agent layer](/agent-layer/home)
```

Ссылка ставится **только** на `agent-layer/home`. На `dev/` из корневой
навигации ссылки нет: рабочий лог сопровождающего команде не адресован.

- [ ] **Шаг 2: Проверить все ссылки раздела вручную**

Wiki не покрыта CI, битые ссылки не поймает никто. Открыть каждую страницу
раздела и убедиться, что все внутренние ссылки ведут в существующие страницы.

- [ ] **Шаг 3: Закоммитить и запушить после подтверждения**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template.wiki" && \
bash "C:/Users/jarin/git/my-projects/1c-aidd-template/template/project/.claude/scripts/commit-block.sh" \
  "wiki: раздел agent layer в корневой навигации" \
  --add-path home.md \
  --body-line "Ссылка ведёт только на продуктовую точку входа; материалы" \
  --body-line "сопровождающего в общую навигацию не выносятся."
```

---

### Задача 9: Приёмка — первая сессия из шаблона (Б7)

- [ ] **Шаг 1: Открыть новую сессию с рабочим каталогом шаблона**

`C:/Users/jarin/git/sollers/EDT-project-template`.

- [ ] **Шаг 2: Проверить пять свойств**

1. Личные skills `aidd-*` видны в перечне skills сессии.
2. Корпоративные skills `mpl-*` видны там же.
3. Указатель `agent-layer-journal` поднялся из памяти автоматически.
4. Журнал читается из клона wiki обычным `Read`.
5. `git status` шаблона пуст.

- [ ] **Шаг 3: Прогнать проверки слоя из нового рабочего места**

```bash
cd "C:/Users/jarin/git/sollers/EDT-project-template" && python tools/ai/mpl-validate-agent-layer.py
cd "C:/Users/jarin/git/sollers/EDT-project-template" && bash tools/ai/mpl-render-claude-layer.sh --check
cd "C:/Users/jarin/git/sollers/EDT-project-template" && bash tools/ai/tests/run-selftests.sh
```

Полный набор self-tests гоняется **один раз** здесь, а не после каждой задачи:
после правок достаточно валидатора и `render --check`.

- [ ] **Шаг 4: Записать факт переезда в журнал**

Первая запись, сделанная по новым правилам: дата, что переехало, какими
коммитами, что проверено. Порядок соблюдается — коммиты уже существуют.

---

## Что вне scope

- `aidd/docs/**` в MBS (42 файла) — по решению человека не трогаем.
- Перенос личного AIDD-слоя в корпоративный: решение «AIDD остаётся личным» в силе.
- MR ветки слоя в `main` шаблона — отдельное решение, от переезда не зависит.
- Разрешения `tools/ai/*.cmd` в `settings.json` и устаревшие имена skills
  (`v8std-tools`, `yaxunit-tests`) в `settings.local.json` MBS — известные
  пробелы, отдельные задачи.
