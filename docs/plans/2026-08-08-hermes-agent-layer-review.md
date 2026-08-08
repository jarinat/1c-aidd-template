# План ревизии корпоративного agent layer (результат Hermes)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read-only ревизия итерации B (agent layer Гермеса) с вердиктом принять/доработать/выбросить по каждому артефакту и отчётом-матрицей.

**Architecture:** Последовательный проход по категориям артефактов (entrypoints → standards → skills → мост/рендер → валидация → helper/fixtures → коммиты → сверка с итерацией A). Каждая задача добавляет секцию в один отчёт и коммитится отдельно. Спорные вердикты собираются в батчи вопросов пользователю, финальные решения фиксируются в отчёте.

**Tech Stack:** Git (read-only команды), Read/Glob/Grep, официальные доки Claude Code / Codex / agentskills.io, донор `1c-aidd-template`.

## Global Constraints

- Спека: `docs/specs/2026-08-08-hermes-agent-layer-review-design.md` (этот репозиторий). План не отменяет её; при конфликте побеждает спека.
- Ревизия **строго read-only** по отношению к трём чужим репозиториям: `hermy-PROSYS-Avtolid` (P), `EDT-project-template` (T), MBS. Ни правок, ни checkout, ни переключения веток, ни запуска скриптов слоя. Разрешены только read-only git-команды (`log`, `show`, `diff`, `status`, `cat-file`) и чтение файлов.
- Пишем только в текущий репозиторий `1c-aidd-template`: отчёт `docs/reviews/2026-08-08-hermes-agent-layer-review.md` и чекбоксы этого плана.
- Пути:
  - P = `C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid` (рабочее дерево на `feature/MPLSYS-4793-edtpt-agent-layer`);
  - T = `C:/Users/jarin/git/sollers/EDT-project-template` (рабочее дерево на `feature/team-ai-tools`, итерация A);
  - D = `C:/Users/jarin/git/my-projects/1c-aidd-template` (донор; здесь же отчёт).
- Пять критериев ревизии для КАЖДОГО артефакта (из спеки, применять все):
  1. соответствие Hermes-промпту (`prompts/hermes-edt-corporate-agent-layer.md`), включая «Критерии завершения»; заявленное без артефактов-доказательств = НЕ проверено;
  2. соответствие официальной механике CLI: Claude не читает `AGENTS.md` нативно (мост обязателен), skills — `.claude/skills/` (Claude) и `.agents/skills/` (Codex), frontmatter по agentskills.io;
  3. инженерное качество 1С-содержания против донора D: не потеряна суть, нет выдуманных API (YAxUnit, Мокито, EDT MCP);
  4. чистота слоёв: нет AIDD-терминологии, личных путей, специфики Avtolid, секретов; расширяемость project/personal описана; namespace `mplsys-` защищён;
  5. переносимость: атомарные cherry-pick'аемые коммиты, без захвата постороннего.
- Формат строки матрицы отчёта (единый для всех секций):
  `| артефакт | находки (кратко, с fact-ссылками путь:строка) | вердикт: принять/доработать/выбросить | решение: engine/user |`
- Вердикт `user` обязателен, если находка спорная, вкусовая или меняет согласованные решения; такие пункты копятся и задаются пользователю батчем в конце задачи (не по одному).
- Русский язык отчёта; терминология метаданных 1С — по правилам донора.
- Каждая задача завершается коммитом отчёта в D: `git add docs/reviews/... docs/plans/... && git commit`. Subject — короткий, по-русски, без тикетов.

---

### Task 0: Каркас отчёта и фиксация объекта ревизии

**Files:**
- Create: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` (в D)

**Interfaces:**
- Produces: файл отчёта с заголовком, фиксацией SHA и пустыми секциями 1–8, которые заполняют задачи 1–8.

- [ ] **Step 1: Зафиксировать фактическое состояние P**

Выполнить и записать вывод (для отчёта):

```bash
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" status -sb
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" rev-parse HEAD
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" log --format="%h %ad %s" --date=short --no-merges develop..HEAD
```

Ожидаемо: ветка `feature/MPLSYS-4793-edtpt-agent-layer`, 13 коммитов `EDTPT-AI:`. Если состояние отличается (ветка переключена, есть незакоммиченные изменения в agent-layer файлах) — зафиксировать в отчёте как ограничение и продолжать по фактическому HEAD.

- [ ] **Step 2: Составить полный список файлов слоя**

```bash
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" diff --stat develop...HEAD
```

Список путей из diff — это генеральная совокупность ревизии. Сверить с ожидаемыми зонами: `AGENTS.md`, `.claude/**`, `.agents/**`, `doc/ai/**`, `tools/ai/**`. Файлы вне этих зон — сразу кандидат в находки задачи 7 (захват постороннего).

- [ ] **Step 3: Создать каркас отчёта**

Создать `docs/reviews/2026-08-08-hermes-agent-layer-review.md` в D:

```markdown
# Ревизия agent layer Hermes (итерация B)

Дата: 2026-08-08
Спека: ../specs/2026-08-08-hermes-agent-layer-review-design.md
Объект: hermy-PROSYS-Avtolid, ветка feature/MPLSYS-4793-edtpt-agent-layer,
HEAD: <SHA из Step 1>
Состав: <N файлов из Step 2>

Формат вердиктов: принять / доработать / выбросить; решение: engine / user.

## 0. Ограничения ревизии

<фактическое состояние P, отклонения, если есть>

## 1. Испытания и отчёт Hermes

## 2. Entrypoints

## 3. Standards

## 4. Skills

## 5. Мост и рендер Claude

## 6. Валидация и self-tests

## 7. Commit helper, fixtures и чистота коммитов

## 8. Сверка с итерацией A (mpl-*)

## 9. Не подтверждено испытаниями

## 10. Вход для дизайна самоулучшения

## 11. Сводка вердиктов и доработки для подпроекта 2
```

- [ ] **Step 4: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Каркас отчёта ревизии agent layer Hermes"
```

---

### Task 1: Испытания и итоговый отчёт Hermes

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секции 1 и 9 (в D)

**Interfaces:**
- Produces: список свойств слоя со статусом «доказано артефактом X» / «заявлено, не доказано» — задачи 2–6 обязаны сверяться с ним, прежде чем засчитывать что-либо как проверенное.

- [ ] **Step 1: Найти артефакты испытаний**

Hermes-промпт требовал: итоговый отчёт (15 пунктов), матрицу испытаний, `.ai-eval/` с логами запусков CLI, validator/self-tests результаты. Искать:

```bash
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" status --short --ignored -- .ai-eval
```

Плюс Glob по P: `.ai-eval/**`, `*.report.md`, `doc/ai/**/report*`; плюс Glob по `C:/ai-agents/hermes/**/*report*` вне репозитория (отчёт мог остаться в workspace Hermes, напр. рядом с worktree `hermy-PROSYS-Avtolid-agent-layer`). Прочитать найденное.

- [ ] **Step 2: Сверить «Критерии завершения» промпта с доказательствами**

Для каждого пункта критериев завершения из `prompts/hermes-edt-corporate-agent-layer.md` (реализован MVP, оба CLI прошли критические сценарии, чистый checkout, композиция с личным слоем, review не меняет файлы, Sonar offline fixture, commit helper не захватывает постороннее, validator проходит, read-only репозитории не тронуты, push не выполнялся) записать: доказательство (файл/лог/коммит) или «не доказано».

Отдельно проверить «read-only репозитории не изменены»:

```bash
git -C "C:/Users/jarin/git/sollers/EDT-project-template" log --format="%h %ad %s" --date=short -5 main
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" log --format="%h %ad %s" --date=short -5 origin/main
```

(Ветка `feature/team-ai-tools` в T — отдельный вопрос задачи 8: она могла быть создана ДО Hermes и не им.)

- [ ] **Step 3: Заполнить секции 1 и 9 отчёта**

Секция 1 — что нашлось и где; секция 9 — итоговый список «заявлено, но не подтверждено» (он же вход для решения: какие испытания повторить в подпроекте 3).

- [ ] **Step 4: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: испытания и отчёт Hermes"
```

---

### Task 2: Entrypoints

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секция 2 (в D)

**Interfaces:**
- Consumes: статусы доказанности из Task 1.
- Produces: вердикты по `AGENTS.md`, `.claude/CLAUDE.md`, `doc/ai/README.md`, `doc/ai/standards/layers.md`; зафиксированная схема слоёв, с которой сверяются задачи 3–6.

- [ ] **Step 1: Прочитать целиком**

Read (P): `AGENTS.md`, `.claude/CLAUDE.md`, `doc/ai/README.md`, `doc/ai/standards/layers.md`, `doc/ai/project/project-rules.template.md`, `doc/ai/project/project-rules.example.md`.

- [ ] **Step 2: Проверить по чек-листу entrypoints**

- `AGENTS.md`: короткий маршрутизатор без дублирования правил? Не содержит Claude-специфики? Совместим с ролью «корневой AGENTS.md принадлежит шаблону»?
- `.claude/CLAUDE.md`: реализует мост корректно (импорт `@AGENTS.md` или эквивалент — сверить с официальной механикой импортов; симлинк недопустим из-за Windows)? Не конфликтует с личным `.claude/CLAUDE.md` разработчика с AIDD (это же имя файла! — как слой ведёт себя, когда у разработчика в проекте уже есть свой `.claude/CLAUDE.md`, как у пользователя в MBS)? Это ключевой вопрос сосуществования — если ответ «перезапишет личный файл», это blocking-находка с решением user.
- `layers.md`: три слоя описаны так, что расширение не требует правки корпоративных файлов? Куда разработчик кладёт личные skills и как избегается shadowing `mplsys-`?
- Языковой и терминологический контроль: русский, нет специфики Avtolid (искать `Grep -i "avtolid|prosys|MPLSYS-47"` по перечисленным файлам), нет AIDD-терминов (`Grep -i "aidd|active_ticket|tasklist|prd"`).

- [ ] **Step 3: Заполнить секцию 2 матрицей и списком вопросов user**

- [ ] **Step 4: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: entrypoints слоя"
```

---

### Task 3: Standards (9 документов)

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секция 3 (в D)

**Interfaces:**
- Consumes: схема слоёв из Task 2.
- Produces: вердикты по каждому документу `doc/ai/standards/*`; список потерь против донора, который используют вердикты задачи 4 (skills ссылаются на standards).

- [ ] **Step 1: Прочитать все 9 документов**

Read (P): `doc/ai/standards/{onec-bsl,bsl-style,onec-queries,testing-yaxunit,code-review,git-commits,agent-tools,language,layers}.md` (layers уже прочитан в Task 2 — в матрице секции 3 не дублировать, дать ссылку).

- [ ] **Step 2: Сверка с донором по парам**

Пары donor→standard (Read соответствующий файл D для каждой):
- `template/project/.claude/rules/core/onec-general.md` → `onec-bsl.md`
- `template/project/.claude/rules/core/code-style.md` → `bsl-style.md`
- `template/project/.claude/skills/1c-query/SKILL.md` → `onec-queries.md`
- `template/project/.claude/skills/yaxunit-tests/SKILL.md` (+ `references/api-reference.md`) → `testing-yaxunit.md`
- `template/project/.claude/rules/core/code-review.md` → `code-review.md`
- `template/project/.claude/rules/core/git-workflow.md` → `git-commits.md`
- `template/project/.claude/rules/core/tool-usage.md` → `agent-tools.md`

Для каждой пары ответить: какие содержательные правила донора потеряны? Потеря оправдана (AIDD/проектная специфика) или это выхолащивание инженерного ядра (например: чтение реквизитов через точку, запросы в циклах, блокировки при проверке уникальности, `ПередЗаписью`/`ПриЗаписи`, привилегированный режим — эти блоки донора обязаны иметь эквивалент или явное объяснение отсутствия)? Что добавлено нового и корректно ли оно?

- [ ] **Step 3: Проверка чистоты и выдумок**

По каждому документу: `Grep -i "aidd|avtolid|prosys"`; выборочная проверка фактических утверждений о платформе/БСП, которые выглядят незнакомо (кандидаты на выдуманный API), — сверить с донором или v8std (MCP `v8std` доступен в этой сессии, использовать для спорных стандартов 1С).

- [ ] **Step 4: Заполнить секцию 3, собрать вопросы user**

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: standards слоя"
```

---

### Task 4: Skills (14 + роль implementer)

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секция 4 (в D)

**Interfaces:**
- Consumes: потери/вердикты standards из Task 3 (skill, ссылающийся на слабый standard, наследует его находки).
- Produces: вердикт по каждому skill; список skills, состав которых меняется (вход секции 11).

Ревизовать канонические `.agents/skills/mplsys-*/SKILL.md` в P (адаптеры `.claude` — задача 5). Группы и порядок:

- [ ] **Step 1: Группа EDT MCP** — `mplsys-edt-mcp`, `mplsys-edt-companion-mcp`, `mplsys-1c-rsv`

Чек-лист: правило «ровно один активный EDT MCP» сохранено? Нет выдуманных tool names/schemas (сверить упоминаемые tools со списком реальных: у донора в `template/project/.claude/skills/1c-*-tools/SKILL.md` и по фактическим MCP этой сессии `mcp__1c-rsv__*`)? Fallback при недоступности описан без подмены сервера?

- [ ] **Step 2: Группа 1С-инженерия** — `mplsys-1c-query`, `mplsys-yaxunit`, `mplsys-1c-bsp`, `mplsys-v8std`, `mplsys-metadata-removal-impact`

Чек-лист: против пар донора (Task 3 Step 2 + `template/project/.claude/skills/{1c-bsp,v8std-tools,1c-metadata-removal-impact}/SKILL.md`). Для `mplsys-yaxunit` отдельно: требует определять фактическую версию YAxUnit и запрещает угадывать API Мокито/ЮТест? `references/yaxunit-api.md` — не устарел ли против донора `references/api-reference.md`?

- [ ] **Step 3: Группа процессов** — `mplsys-code-review`, `mplsys-address-review`, `mplsys-fix-sonar`, `mplsys-commit`, `mplsys-project-onboarding`, `mplsys-implement`, роль `.agents/roles/mplsys-implementer/ROLE.md`

Чек-лист: review строго read-only? address-review трогает только выбранные замечания? fix-sonar работает с offline fixture и не верит Sonar вслепую? commit не захватывает постороннее и требует явные пути? onboarding отделяет факты от догадок? `mplsys-implement`+роль: не протащен ли фактически AIDD-lifecycle под другим именем (красная линия из требований пользователя — «без навязывания воркфлоу»)? Роль `.agents/roles/` — вообще стандартный ли это механизм Codex или изобретение (сверить с доками Codex; если изобретение — вердикт user).

- [ ] **Step 4: Кросс-проверка всех 14 frontmatter**

По каждому SKILL.md: frontmatter соответствует agentskills.io (`name` = имя каталога, `description` со внятными triggers); атомарность (skill не требует запуска другого skill); нет ссылок на личный шаблон/пути Hermes.

- [ ] **Step 5: Заполнить секцию 4, батч вопросов user**

- [ ] **Step 6: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: skills слоя"
```

---

### Task 5: Мост и рендер Claude

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секция 5 (в D)

**Interfaces:**
- Consumes: вердикты канонических skills из Task 4.
- Produces: вердикт по архитектуре моста (рендер vs альтернативы) — ключевой вход секции 11.

- [ ] **Step 1: Прочитать механизм**

Read (P): `tools/ai/mplsys-render-claude-layer.sh`, `.claude/rules/mplsys/mplsys.md`, 2–3 адаптера `.claude/skills/mplsys-*/SKILL.md` (например `mplsys-1c-query`, `mplsys-code-review`, `mplsys-implement`) и `.claude/agents/mplsys-implementer.md`.

- [ ] **Step 2: Проверить соответствие адаптеров каноническим**

Для каждого из 14 skills сравнить `.claude/skills/X/SKILL.md` с `.agents/skills/X/SKILL.md`:

```bash
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" diff --no-index --stat -- .agents/skills .claude/skills
```

(если diff --no-index недоступен в этой форме — попарно). Вопросы: адаптер = точная копия или тонкая обёртка? Есть ли «вторая копия процесса» (запрещена промптом)? Рендер детерминирован и идемпотентен (повторный прогон не меняет файлы)? Как ловится дрейф — validator?

- [ ] **Step 3: Оценить архитектуру рендера против альтернатив**

Зафиксировать в отчёте сравнение: рендер-скрипт (как есть) vs идентичные копии под контролем валидатора vs симлинки (отвергнуты: Windows). Критерий — стоимость для обычного разработчика команды: что он должен запускать и когда, что происходит при забытом рендере. Вердикт — предложение engine, решение user.

- [ ] **Step 4: Заполнить секцию 5**

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: мост и рендер Claude"
```

---

### Task 6: Валидация и self-tests

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секция 6 (в D)

**Interfaces:**
- Consumes: инварианты слоя из задач 2–5 (что валидатор ДОЛЖЕН проверять).
- Produces: вердикт по validator/self-tests; список инвариантов без автоматической проверки (вход секции 11).

- [ ] **Step 1: Прочитать код**

Read (P): `tools/ai/mplsys-validate-agent-layer.py`, `tools/ai/tests/run-selftests.sh`, `tools/ai/tests/fixtures/sonar-issues.sample.json`.

- [ ] **Step 2: Сверить покрытие validator с требованиями промпта**

Промпт требовал минимум: обязательные файлы, YAML frontmatter, имя каталога = `name`, шаблон `^mplsys-[a-z0-9-]+$`, уникальность, битые ссылки, соответствие адаптеров каноническим, отсутствие второй копии процесса, отсутствие AIDD-терминов в новых tracked-файлах, отсутствие ссылок на личный шаблон, корректность `.gitignore`, отсутствие абсолютных путей/секретов, shadowing namespace. Для каждого пункта: покрыт кодом / не покрыт. НЕ запускать скрипты (read-only ограничение) — только чтение кода; выполнимость проверяется в подпроекте 3.

- [ ] **Step 3: Оценить переносимость валидатора**

Python + bash в команде Windows-разработчиков 1С: на чём это будет запускаться у обычного разработчика и в CI шаблона? Если ответ «ни на чём» — находка с вердиктом доработать (варианты: OneScript, PowerShell, CI-job). Решение user.

- [ ] **Step 4: Заполнить секцию 6**

- [ ] **Step 5: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: валидация и self-tests"
```

---

### Task 7: Commit helper, fixtures и чистота коммитов

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секция 7 (в D)

**Interfaces:**
- Consumes: генеральная совокупность файлов из Task 0 Step 2.
- Produces: вердикт по helper; карта «коммит → файлы → атомарность» для подпроекта 2 (порядок cherry-pick).

- [ ] **Step 1: Прочитать helper**

Read (P): `tools/ai/mplsys-commit.sh`. Чек-лист промпта: только явные пути, предварительный status/diff, dry-run, отказ при пустом сообщении, без push, exit codes, пути с пробелами, точки входа Windows/Linux или документированное обоснование. Сверить с донором `template/project/.claude/scripts/commit-block.sh`: что helper потерял/упростил. Отдельно: `.sh`-only в Windows-команде — та же находка о переносимости, что и в Task 6 Step 3.

- [ ] **Step 2: Проверить каждый из 13 коммитов**

```bash
git -C "C:/ai-agents/hermes/workspace/git/sollers/hermy-PROSYS-Avtolid" show --stat <sha>
```

для каждого `EDTPT-AI:` коммита (список из Task 0 Step 1). Вопросы: только agent-layer файлы (нет захвата `src/**`, пользовательских файлов)? Границы осмысленны для cherry-pick? Мешают ли merge-коммиты веток эксперимента переносу (если да — в подпроект 2 идёт рекомендация переносить squash'ем или диапазоном, зафиксировать)?

- [ ] **Step 3: Заполнить секцию 7 (включая карту cherry-pick)**

- [ ] **Step 4: Commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия: commit helper и чистота коммитов"
```

---

### Task 8: Сверка с итерацией A и финализация

**Files:**
- Modify: `docs/reviews/2026-08-08-hermes-agent-layer-review.md` — секции 8, 10, 11 (в D)

**Interfaces:**
- Consumes: все секции 1–7.
- Produces: финальный отчёт с сводкой вердиктов; батч открытых вопросов пользователю; список доработок для подпроекта 2.

- [ ] **Step 1: Сверка с итерацией A**

Список файлов A: `git -C "C:/Users/jarin/git/sollers/EDT-project-template" show --stat 7fef644`. Вопрос один: есть ли в A содержание, отсутствующее в B (сравнивать по назначению файла, не по имени: `doc/standards/sonar.md` A ↔ `mplsys-fix-sonar` B и т.п.)? Выборочно прочитать 2–3 файла A, аналоги которых в B слабее всего по задачам 3–4. Итог секции 8: «A устарела, удалить ветку» либо список фрагментов A для переноса.

- [ ] **Step 2: Секция 10 — вход для самоулучшения**

На основе всего увиденного: есть ли в слое B хоть какой-то механизм накопления опыта (аналог pitfalls, learnings, project-rules пополнение)? Чего не хватает для модели пользователя «стандартизированный пост-задачный артефакт → центральная курация»? Только констатация и требования — без дизайна.

- [ ] **Step 3: Секция 11 — сводка**

Таблица: все артефакты → вердикт → решение. Отдельный список: доработки для подпроекта 2 (упорядоченные), открытые вопросы user (батч).

- [ ] **Step 4: Задать пользователю батч вопросов**

Все накопленные пункты с решением `user` — одним структурированным сообщением/AskUserQuestion-батчами. Ответы вписать в отчёт (колонка «решение»), статусы вердиктов обновить.

- [ ] **Step 5: Финальный commit**

```bash
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" add docs/reviews/2026-08-08-hermes-agent-layer-review.md docs/plans/2026-08-08-hermes-agent-layer-review.md
git -C "C:/Users/jarin/git/my-projects/1c-aidd-template" commit -m "Ревизия agent layer Hermes: итоги и решения"
```

---

## Definition of Done подпроекта 1

- Отчёт заполнен по всем 11 секциям, у каждого артефакта слоя есть вердикт.
- Все вопросы `user` заданы и решения вписаны.
- Секция 9 явно перечисляет непроверенные свойства (план их проверки — подпроект 3).
- Секция 11 содержит упорядоченный список доработок для подпроекта 2.
- В P, T и MBS не внесено ни одного изменения.
