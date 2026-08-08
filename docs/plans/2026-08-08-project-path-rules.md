# План реализации: path-scoped правила проектного слоя (Б2)

> **Для исполнителя:** шаги отмечаются чекбоксами. Спека:
> `../specs/2026-08-08-project-path-rules-design.md`.

**Цель:** дать проектному слою правила, привязанные к путям, так чтобы
согласованность таблицы-роутера и файлов держал валидатор, а не аккуратность
автора.

**Архитектура:** каталог `doc/ai/project/paths/` с файлами-правилами; каждый
файл открывается frontmatter с единственным ключом `paths` (блочный список
глобов, синтаксис совпадает с нативным у Claude Code); `paths/README.md` несёт
таблицу-роутер; `AGENTS.md` несёт всегда действующий инвариант «сверься с
таблицей путей»; валидатор сверяет таблицу и файлы в обе стороны. Отдельно
закрывается латентный дефект: корпоративные block-list сканы обходили
`doc/ai/project/` и уронили бы валидатор на заполненных проектных правилах.

**Стек:** Python 3.9+ (валидатор), bash (self-tests), Markdown.

## Глобальные ограничения

- Репозиторий `EDT-project-template`, ветка `feature/team-ai-tools-v2`.
- Вся корпоративная проза — на русском (`doc/ai/standards/language.md`).
- Корпоративные отслеживаемые файлы не содержат имён проектов, терминов личного
  процесса (`AIDD`, `PRD`, `tasklist`), абсолютных путей и секретов.
- Задачи — единицы проверки, а не коммитов. Итог укладывается в **один** коммит
  в конце (критерий готовности спеки), push не делается.
- Перед коммитом зелёными обязаны быть: `mpl-validate-agent-layer.py`,
  `mpl-render-claude-layer.sh --check`, `run-selftests.sh`.
- `run-selftests.sh` нельзя редактировать, пока он выполняется: bash читает
  скрипт по смещению, и правка на ходу ломает прогон.

---

### Задача 1: проектные файлы вне корпоративных контентных сканов

**Файлы:**
- Изменить: `tools/ai/mpl-validate-agent-layer.py` (`corporate_files`
  соседствует с новым `scannable_files`; `_scan`; `check_corporate_language`)
- Тест: `tools/ai/tests/run-selftests.sh`

**Интерфейсы:**
- Производит: `Validator.scannable_files() -> list[str]` и
  `Validator._is_project_owned(rel: str) -> bool`. Задача 3 их не использует;
  `check_links` продолжает работать на полном `corporate_files()`.

- [ ] **Шаг 1: написать падающий тест**

В `tools/ai/tests/run-selftests.sh` перед блоком
`== validator: кодировка вывода ==` вставить:

```bash
printf '\n== validator: path-правила проекта ==\n'

# Файлы слоя 2 законно содержат имя проекта и термины локального процесса
# команды. Корпоративные block-list сканы к ним не применяются, иначе заполнить
# проектные правила означало бы уронить валидатор.
c="$TMPROOT/c-project-owned"; build_golden "$c"
cat > "$c/doc/ai/project/project-rules.md" <<'PROJECTRULES'
# Правила проекта

## Подтверждённые факты

- Конфигурация PROSYS-Avtolid; задачи ведутся через PRD и tasklist.

## Допущения

## Открытые вопросы

## Решения человека
PROJECTRULES
expect_pass "$c" "заполненные правила проекта не подпадают под корпоративные сканы"
```

- [ ] **Шаг 2: убедиться, что тест падает**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: `FAIL  заполненные правила проекта не подпадают под корпоративные
сканы` — валидатор ругается на проектный маркер и терминологию процесса.

- [ ] **Шаг 3: реализовать разделение**

В `mpl-validate-agent-layer.py` сразу после метода `corporate_files` добавить:

```python
    @staticmethod
    def _is_project_owned(rel: str) -> bool:
        """True для файла, которым владеет слой проекта, а не корпоративный слой.

        Под `doc/ai/project/` корпоративными поставками остаются только шаблон и
        пример: они обязаны быть переносимыми. Всё остальное там пишет команда
        проекта, и оно законно содержит имя проекта, префиксы метаданных и
        термины локального рабочего процесса.
        """
        if not rel.startswith("doc/ai/project/"):
            return False
        name = os.path.basename(rel)
        return not (name.endswith(".template.md") or name.endswith(".example.md"))

    def scannable_files(self) -> list[str]:
        """Файлы, к которым применяются block-list сканы и языковой guard.

        Это `corporate_files()` минус файлы слоя проекта. Проверки существования,
        отслеживания и битых ссылок продолжают работать на полном наборе:
        исключение касается только содержимого.
        """
        return [rel for rel in self.corporate_files() if not self._is_project_owned(rel)]
```

Заменить источник файлов в двух местах:

```python
    def _scan(self, patterns, label_files=None) -> None:
        files = label_files if label_files is not None else self.scannable_files()
```

```python
        for rel in self.scannable_files():
            if not rel.endswith(".md"):
                continue
            text = self.read(rel)
            if text is None:
                continue
            self.checks += 1
            masked = self._mask_technical(text)
```

(второй фрагмент — начало цикла в `check_corporate_language`; в `check_links`
источник **не** менять).

- [ ] **Шаг 4: убедиться, что тест проходит**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: `PASS  заполненные правила проекта не подпадают под корпоративные
сканы`, остальные случаи без изменений.

---

### Задача 2: артефакты каталога `paths/` и обязательный инвентарь

**Файлы:**
- Создать: `doc/ai/project/paths/README.md`
- Создать: `doc/ai/project/paths/sources.example.md`
- Изменить: `doc/ai/project/project-rules.template.md` (указатель)
- Изменить: `tools/ai/mpl-validate-agent-layer.py` (`required_inventory`)
- Тест: `tools/ai/tests/run-selftests.sh`

**Интерфейсы:**
- Производит: путь `doc/ai/project/paths/README.md` с таблицей-роутером и
  `doc/ai/project/paths/sources.example.md` как эталон формата. Задача 3
  разбирает frontmatter этого формата, задача 4 — таблицу из README.

- [ ] **Шаг 1: написать падающий тест**

Дописать в тот же блок `== validator: path-правила проекта ==`:

```bash
c="$TMPROOT/c-paths-readme-missing"; build_golden "$c"
rm -f "$c/doc/ai/project/paths/README.md"
expect_fail "$c" "отсутствует обязательный файл: doc/ai/project/paths/README.md" \
  "детектирует отсутствующую таблицу-роутер path-правил"
```

- [ ] **Шаг 2: убедиться, что тест падает**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: `FAIL  детектирует отсутствующую таблицу-роутер path-правил` —
файла ещё нет ни в шаблоне, ни в инвентаре, `rm -f` ничего не удаляет, а
валидатор его не требует.

- [ ] **Шаг 3: создать `doc/ai/project/paths/README.md`**

```markdown
# Правила проекта по путям

Правила, которые действуют не на весь репозиторий, а на конкретную зону дерева:
исходники основной конфигурации, расширения, тесты, generated-каталоги,
tooling. Это слой проекта — см. [layers.md](../../standards/layers.md).
Корпоративные стандарты остаются переносимыми и по путям не скоупятся.

Содержимое этого каталога, кроме файлов с маркером `.example.`, принадлежит
команде проекта: там законны имя проекта, префиксы метаданных и термины
локального процесса.

## Как это работает

`AGENTS.md` несёт всегда действующий инвариант: перед тем как планировать или
менять файл, агент сверяется с таблицей ниже и читает каждое правило, чьи глобы
совпадают с путём. Таблица — точка входа, а не украшение.

## Как добавить зону

1. Создай `<зона>.md` в этом каталоге по формату
   [`sources.example.md`](sources.example.md): frontmatter с единственным ключом
   `paths` — блочным списком глобов, затем правила.
2. Добавь строку в таблицу. Глобы перечисляй через запятую в обратных кавычках;
   порядок значения не имеет, но набор обязан совпасть с frontmatter файла.
3. Прогони `python3 tools/ai/mpl-validate-agent-layer.py`: он держит
   согласованность таблицы и файлов в обе стороны.

Синтаксис frontmatter намеренно совпадает с нативным форматом Claude Code,
поэтому файл остаётся переносимым без переписывания.

## Таблица

| Пути | Правило | Что регулирует |
|------|---------|----------------|

Пустая таблица — корректное состояние: проект ещё не завёл ни одной зоны.
```

- [ ] **Шаг 4: создать `doc/ai/project/paths/sources.example.md`**

```markdown
---
paths:
  - "src/cf/**"
  - "src/cfe/*/**"
---

# Пример: исходники конфигурации и расширений

> Поставляемый шаблоном пример формата. Скопируй его под свою зону, переименуй
> без маркера `.example.` и приведи глобы и правила к своему репозиторию. Файлы
> с маркером `.example.` в таблицу-роутер не входят и валидатором с ней не
> сверяются.

- Прямые изменения исходников основной конфигурации допустимы; служебные файлы
  среды разработки вручную не редактируются.
- Библиотечный и поставляемый код меняется только при реальной необходимости;
  предпочтительны переопределяемые точки и механизмы расширения.
- Для поиска сущностей 1С используй настроенный EDT MCP; широкий текстовый
  поиск по дереву исходников — запасной вариант или подтверждение найденных
  кандидатов.
```

- [ ] **Шаг 5: добавить указатель в шаблон правил проекта**

В `doc/ai/project/project-rules.template.md` после вводной цитаты (перед
`## Подтверждённые факты`) вставить:

```markdown
> Правила, действующие только на часть дерева, живут отдельно:
> [`paths/README.md`](paths/README.md).
```

- [ ] **Шаг 6: внести оба файла в обязательный инвентарь**

В `required_inventory` после строки `"doc/ai/project/project-rules.example.md",`
добавить:

```python
                    "doc/ai/project/paths/README.md",
                    "doc/ai/project/paths/sources.example.md",
```

- [ ] **Шаг 7: убедиться, что тест проходит**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: `PASS  детектирует отсутствующую таблицу-роутер path-правил` и
`PASS  реальный слой проходит`.

---

### Задача 3: разбор frontmatter path-правила

**Файлы:**
- Изменить: `tools/ai/mpl-validate-agent-layer.py` (константа-regex рядом с
  `NAME_RE`; метод `parse_path_globs`; новый `check_project_path_rules`;
  регистрация в `run`)
- Тест: `tools/ai/tests/run-selftests.sh`

**Интерфейсы:**
- Потребляет: формат файла из задачи 2, `FRONTMATTER_FORBIDDEN_CONTROL_RE`.
- Производит: `Validator.parse_path_globs(text: str) -> tuple[list[str], str]` —
  возвращает `(глобы, "")` при успехе и `([], причина)` при отказе;
  `Validator.check_project_path_rules() -> None`. Задача 4 дополняет тот же
  метод сверкой с таблицей.

- [ ] **Шаг 1: написать падающие тесты**

Дописать в блок `== validator: path-правила проекта ==`:

```bash
c="$TMPROOT/c-path-no-frontmatter"; build_golden "$c"
printf '# Зона без frontmatter\n\n- правило\n' > "$c/doc/ai/project/paths/sources.md"
expect_fail "$c" "некорректный frontmatter path-правила" \
  "детектирует path-правило без frontmatter"

c="$TMPROOT/c-path-empty-list"; build_golden "$c"
printf -- '---\npaths:\n---\n\n# Пустой список\n' > "$c/doc/ai/project/paths/sources.md"
expect_fail "$c" "некорректный frontmatter path-правила" \
  "детектирует пустой список paths"

c="$TMPROOT/c-path-extra-key"; build_golden "$c"
printf -- '---\npaths:\n  - "src/cf/**"\nname: лишний\n---\n\n# Лишний ключ\n' \
  > "$c/doc/ai/project/paths/sources.md"
expect_fail "$c" "некорректный frontmatter path-правила" \
  "детектирует лишний ключ во frontmatter path-правила"
```

- [ ] **Шаг 2: убедиться, что тесты падают**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: три `FAIL` — метод разбора ещё не существует, валидатор возвращает 0.

- [ ] **Шаг 3: добавить regex-константу**

После строки `NAME_RE = re.compile(r"^mpl-[a-z0-9-]+$")` добавить:

```python
# Элемент блочного YAML-списка в frontmatter проектного path-правила:
# `  - "src/cf/**"`, `  - 'src/cf/**'` или `  - src/cf/**`. Кавычки снимаются
# при разборе. Существующий parse_frontmatter намеренно отвергает списки —
# он охраняет frontmatter skills, и ослаблять его нельзя, поэтому здесь
# отдельный узкий разбор.
PATH_RULE_ITEM_RE = re.compile(r'^\s*-\s+(?:"([^"]*)"|\'([^\']*)\'|(\S.*?))\s*$')
# Строка таблицы-роутера ровно из трёх колонок.
PATH_ROUTER_ROW_RE = re.compile(r"^\|([^|]*)\|([^|]*)\|([^|]*)\|$")
PATH_ROUTER_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
```

- [ ] **Шаг 4: реализовать разбор**

В классе `Validator` после метода `parse_frontmatter` добавить:

```python
    @classmethod
    def parse_path_globs(cls, text: str) -> tuple[list[str], str]:
        """Вернуть (глобы, причина отказа) для frontmatter проектного path-правила.

        Поддерживается ровно одна форма: frontmatter, открытый и закрытый строкой
        `---`, с единственным ключом `paths`, значение которого — непустой блочный
        список непустых однострочных глобов. Кавычки вокруг глоба снимаются. Всё
        остальное отвергается: поверхность держится крошечной и однозначной, а
        синтаксис совпадает с нативным форматом Claude Code.
        """
        text = text.replace("\r\n", "\n")
        if FRONTMATTER_FORBIDDEN_CONTROL_RE.search(text):
            return [], "управляющий символ или Unicode-разрыв строки"
        lines = text.splitlines()
        if not lines or lines[0] != "---":
            return [], "нет открывающего ---"
        try:
            end = lines.index("---", 1)
        except ValueError:
            return [], "нет закрывающего ---"
        body = lines[1:end]
        if not body or body[0].strip() != "paths:":
            return [], "первой строкой frontmatter должен быть ключ paths:"
        globs: list[str] = []
        for line in body[1:]:
            match = PATH_RULE_ITEM_RE.match(line)
            if not match:
                return [], f"строка не является элементом списка глобов: {line.strip()!r}"
            value = next(g for g in match.groups() if g is not None).strip()
            if not value:
                return [], "пустой глоб в списке paths"
            globs.append(value)
        if not globs:
            return [], "список paths пуст"
        return globs, ""
```

- [ ] **Шаг 5: реализовать проверку формата**

После метода `check_project_rules_structure` добавить:

```python
    def path_rule_files(self) -> dict[str, list[str]]:
        """Имя файла -> глобы для каждого проектного path-правила.

        README и файлы с маркером `.example.` исключены: первый несёт таблицу,
        вторые поставляются шаблоном как образец формата.
        """
        base = "doc/ai/project/paths"
        root = self.path(base)
        result: dict[str, list[str]] = {}
        if not os.path.isdir(root):
            return result
        for name in sorted(os.listdir(root)):
            if not name.endswith(".md") or name == "README.md" or ".example." in name:
                continue
            rel = f"{base}/{name}"
            text = self.read(rel)
            self.checks += 1
            if text is None:
                self.err(f"{rel}: не читается как UTF-8")
                continue
            globs, problem = self.parse_path_globs(text)
            self.checks += 1
            if problem:
                self.err(f"{rel}: некорректный frontmatter path-правила — {problem}")
                continue
            result[name] = globs
        return result

    def check_project_path_rules(self) -> None:
        """Проектные path-правила: формат файла и согласованность с таблицей.

        Каталог принадлежит слою проекта, но сам МЕХАНИЗМ корпоративный, поэтому
        инвариант держит validator, а не аккуратность автора.
        """
        readme_rel = "doc/ai/project/paths/README.md"
        readme = self.read(readme_rel)
        self.checks += 1
        if readme is None:
            self.err(f"отсутствует {readme_rel} (таблица-роутер path-правил проекта)")
            return
        self.path_rule_files()
```

- [ ] **Шаг 6: зарегистрировать проверку**

В методе `run` после строки `self.check_project_rules_structure()` добавить:

```python
        self.check_project_path_rules()
```

- [ ] **Шаг 7: убедиться, что тесты проходят**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: три `PASS` из шага 1 и `PASS  реальный слой проходит`.

---

### Задача 4: сверка таблицы-роутера с файлами

**Файлы:**
- Изменить: `tools/ai/mpl-validate-agent-layer.py` (`_path_router_rows`,
  тело `check_project_path_rules`)
- Тест: `tools/ai/tests/run-selftests.sh`

**Интерфейсы:**
- Потребляет: `path_rule_files()` и константы из задачи 3.
- Производит: `Validator._path_router_rows(text: str) -> list[tuple[set[str], str]]` —
  пары «набор глобов, имя файла-цели» из таблицы.

- [ ] **Шаг 1: написать падающие тесты**

Дописать в блок `== validator: path-правила проекта ==`:

```bash
c="$TMPROOT/c-path-unlisted"; build_golden "$c"
printf -- '---\npaths:\n  - "src/cf/**"\n---\n\n# Зона вне таблицы\n' \
  > "$c/doc/ai/project/paths/sources.md"
expect_fail "$c" "не названо в таблице-роутере" "детектирует path-правило вне таблицы"

c="$TMPROOT/c-path-glob-mismatch"; build_golden "$c"
printf -- '---\npaths:\n  - "src/cf/**"\n---\n\n# Зона\n' \
  > "$c/doc/ai/project/paths/sources.md"
printf '| `src/cfe/**` | [sources.md](sources.md) | зона |\n' \
  >> "$c/doc/ai/project/paths/README.md"
expect_fail "$c" "расходятся с frontmatter" \
  "детектирует расхождение глобов таблицы и файла"

c="$TMPROOT/c-path-dangling"; build_golden "$c"
printf '| `src/cf/**` | [missing.md](missing.md) | зона |\n' \
  >> "$c/doc/ai/project/paths/README.md"
expect_fail "$c" "но такого path-правила нет" "детектирует строку таблицы без файла"
```

- [ ] **Шаг 2: убедиться, что тесты падают**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: три `FAIL`. У случая `dangling` валидатор уже вернёт код 1 по чужому
сообщению `битая относительная ссылка`, но `expect_fail` требует ещё и
совпадения своего паттерна, поэтому случай честно падает до шага 4.

- [ ] **Шаг 3: реализовать разбор таблицы**

В классе `Validator` перед `check_project_path_rules` добавить:

```python
    @staticmethod
    def _path_router_rows(text: str) -> list[tuple[set[str], str]]:
        """Пары «набор глобов, имя файла» из таблицы-роутера.

        Строка заголовка и строка-разделитель пропускаются: у первой нет ссылки,
        вторая состоит только из дефисов и двоеточий. Глобы перечисляются через
        запятую в обратных кавычках, сравниваются как множество, поэтому порядок
        значения не имеет.
        """
        rows: list[tuple[set[str], str]] = []
        for line in text.splitlines():
            match = PATH_ROUTER_ROW_RE.match(line.strip())
            if not match:
                continue
            cells = [c.strip() for c in match.groups()]
            if set(cells[0]) <= set("-: ") and set(cells[1]) <= set("-: "):
                continue
            link = PATH_ROUTER_LINK_RE.search(cells[1])
            if link is None:
                continue
            globs = {g.strip().strip("`") for g in cells[0].split(",") if g.strip()}
            rows.append((globs, link.group(1).strip()))
        return rows
```

- [ ] **Шаг 4: дополнить проверку сверкой**

Заменить строку `        self.path_rule_files()` в `check_project_path_rules` на:

```python
        rule_files = self.path_rule_files()
        listed = {
            target: globs
            for globs, target in self._path_router_rows(readme)
            if ".example." not in target
        }

        for name, globs in rule_files.items():
            self.checks += 1
            if name not in listed:
                self.err(f"{readme_rel}: path-правило {name} не названо в таблице-роутере")
                continue
            self.checks += 1
            if listed[name] != set(globs):
                self.err(f"{readme_rel}: глобы строки {name} расходятся с frontmatter "
                         f"файла (таблица: {sorted(listed[name])}, "
                         f"файл: {sorted(set(globs))})")

        for target in listed:
            self.checks += 1
            if target not in rule_files:
                self.err(f"{readme_rel}: строка таблицы ведёт в {target}, "
                         "но такого path-правила нет")
```

- [ ] **Шаг 5: убедиться, что тесты проходят**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: три `PASS` из шага 1 и `PASS  реальный слой проходит` (пустая таблица
законна).

---

### Задача 5: якорь в AGENTS.md и его защита

**Файлы:**
- Изменить: `AGENTS.md` (раздел `### Всегда действующие инварианты`)
- Изменить: `tools/ai/mpl-validate-agent-layer.py` (список `safety` в
  `check_routing_section`)
- Тест: `tools/ai/tests/run-selftests.sh`

**Интерфейсы:**
- Потребляет: путь `doc/ai/project/paths/README.md` из задачи 2.
- Производит: инвариант в всегда загружаемой секции `AGENTS.md`.

- [ ] **Шаг 1: написать падающий тест**

Дописать в блок `== validator: path-правила проекта ==`:

```bash
c="$TMPROOT/c-agents-paths-anchor"; build_golden "$c"
sed -i '/doc\/ai\/project\/paths\/README\.md/d' "$c/AGENTS.md"
expect_fail "$c" "маршрутизация к path-правилам проекта" \
  "детектирует утрату инварианта path-правил в AGENTS.md"
```

- [ ] **Шаг 2: убедиться, что тест падает**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: `FAIL  детектирует утрату инварианта path-правил в AGENTS.md` —
инварианта ещё нет, `sed` ничего не удаляет, валидатор возвращает 0.

- [ ] **Шаг 3: добавить инвариант в AGENTS.md**

В разделе `### Всегда действующие инварианты` после пункта
`- **Сначала прочитай skill.** ...` вставить:

```markdown
- **Правила по путям проекта.** Перед тем как планировать или менять файл,
  сверься с таблицей путей в
  [`doc/ai/project/paths/README.md`](doc/ai/project/paths/README.md) и прочитай
  каждое правило, чьи глобы совпадают с путём. Проектное правило по путям
  уточняет корпоративный стандарт, но не отключает skill `mpl-*` и правило
  безопасности.
```

- [ ] **Шаг 4: защитить инвариант проверкой**

В `check_routing_section` в список `safety` добавить третий элемент:

```python
            (re.compile(r"таблиц\w*\s+путей.{0,240}doc/ai/project/paths", re.I | re.S),
             "маршрутизация к path-правилам проекта"),
```

- [ ] **Шаг 5: убедиться, что тест проходит**

Запустить: `bash tools/ai/tests/run-selftests.sh`
Ожидание: `PASS  детектирует утрату инварианта path-правил в AGENTS.md`,
итог `NN пройдено, 0 провалено`.

---

### Задача 6: полный гейт и коммит

**Файлы:**
- Изменить: `../roadmap-team-agent-layer.md` в мета-репозитории (отдельный
  коммит, вне репозитория шаблона)

- [ ] **Шаг 1: прогнать полный гейт**

Запустить: `bash tools/ai/tests/ci-check.sh`
Ожидание: `OK: инварианты agent layer соблюдены`, `render --check:
сгенерированный Claude-слой актуален`, `NN пройдено, 0 провалено`, код 0.

- [ ] **Шаг 2: предпросмотр коммита**

```bash
bash tools/ai/mpl-commit.sh --dry-run \
  --path AGENTS.md \
  --path doc/ai/project/paths/README.md \
  --path doc/ai/project/paths/sources.example.md \
  --path doc/ai/project/project-rules.template.md \
  --path tools/ai/mpl-validate-agent-layer.py \
  --path tools/ai/tests/run-selftests.sh \
  --message "Agent layer: path-scoped правила проектного слоя"
```

Проверить: в diff только перечисленные пути, нет секретов и абсолютных путей.

- [ ] **Шаг 3: коммит**

Тот же вызов без `--dry-run`, с телом сообщения: что появилось (каталог
`paths/`, формат frontmatter, таблица-роутер, якорь в `AGENTS.md`), какой
латентный дефект закрыт (корпоративные сканы обходили `doc/ai/project/`) и
результаты проверок. Push не делать.

- [ ] **Шаг 4: обновить roadmap**

В мета-репозитории отметить Б2 закрытым, назвать хеш коммита и зафиксировать
асимметрию механизмов Claude/Codex как основание не начинать этап 2. Коммит —
через `.claude/scripts/commit-block.sh`.
