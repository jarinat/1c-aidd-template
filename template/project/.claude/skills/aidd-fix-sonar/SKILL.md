---
name: aidd-fix-sonar
description: >
  Разбор и исправление замечаний SonarQube для конкретного Pull Request в
  1С/EDT проекте. Используй, когда пользователь просит скачать, проверить,
  сгруппировать или исправить Sonar issues указанного PR с фиксацией решений в
  AIDD review. SonarQube в этом сценарии используется только для чтения.
---

# AIDD Fix Sonar

Используй `tools/scripts/download-sonar-issues.os` как единственный entrypoint
выгрузки Sonar issues. Сохраняй инженерные решения в
`aidd/docs/review/<ticket>.md` и применяй принятые исправления через
`.claude/skills/aidd-fix-review/SKILL.md`.

Source of truth:

- lifecycle review: `.claude/rules/core/aidd-workflow.md` и
  `.claude/rules/core/aidd-artifacts.md`;
- политика review: `.claude/rules/core/code-review.md`;
- выбор инструментов: `.claude/rules/core/tool-usage.md`;
- project-specific исключения: `.claude/rules/project/*.md` и
  `.claude/rules/paths/*.md`;
- исправление принятого `RV-XXX`:
  `.claude/skills/aidd-fix-review/SKILL.md`.

## Границы

- Один запуск работает только с одним явно указанным PR.
- SonarQube используется read-only: не меняй статусы issues, assignee, tags,
  comments, quality profile или параметры правил через API.
- Не считай Sonar issue безусловной командой на изменение кода. Проверяй
  правило, точный исходник, diff PR и project-specific правила.
- Не вшивай в skill префиксы, имена объектов и исключения отдельного проекта.
- Не считай этот сценарий полным AIDD review изменений: он импортирует и
  обрабатывает только Sonar-находки.
- Security Hotspots не входят в scope первой версии: используемый API
  выгружает issues, но не hotspot review. Не заявляй, что hotspots проверены.
- Не добавляй generated report в commit и не записывай в него токен.
- Не делай commit.

## Критерии решения

Классифицируй связную группу issues одним из вариантов:

- `FIX_CANDIDATE` — нарушение подтверждено кодом и действующими правилами;
- `JUSTIFIED_EXCEPTION_CANDIDATE` — отклонение подтверждено явным
  project/path rule или неизменяемым внешним контрактом;
- `RULE_CONFIGURATION_CANDIDATE` — повторяющийся конфликт анализатора с
  подтвержденной политикой проекта;
- `BLOCKED` — исходник, правило, diff или обязательный контекст недоступен.

Не группируй issues только потому, что у них одинаковый rule key. Одна запись
`RV-XXX` может ссылаться на несколько Sonar issue keys только когда у них одна
причина, одно решение и общий проверяемый scope.

### LineLength

- Общий предел — 120 символов; по умолчанию предлагай исправление.
- Не считай длину до 130 автоматическим исключением.
- Сначала проверь, можно ли перенести выражение или разделить строковый литерал
  без изменения результирующего текста.
- Для одного намеренно неделимого пользовательского сообщения допускай длину
  больше 120 и 130 как `JUSTIFIED_EXCEPTION_CANDIDATE`; сначала докажи, что
  строка действительно является таким сообщением, а не составным выражением.
- В остальных случаях предлагай исключение только при доказанном ограничении:
  перенос меняет формат внешнего контракта или другой подтвержденный результат.
- Собирай однотипные спорные случаи в одну группу решения, не задавай вопрос по
  каждой строке отдельно.

### Смешение кириллицы и латиницы

- Прочитай `.claude/rules/project/naming.md` и релевантные path rules.
- Если идентификатор следует подтвержденному соглашению текущего проекта,
  классифицируй его как `JUSTIFIED_EXCEPTION_CANDIDATE` или
  `RULE_CONFIGURATION_CANDIDATE`.
- Если соглашение не зафиксировано, не переноси пример из другого проекта:
  собери одну группу и запроси решение пользователя.
- Не переименовывай объект метаданных или его использования только ради
  устранения анализаторного шума.

## Алгоритм

1. Определи ticket id из аргумента или `aidd/docs/.active_ticket`. Если ticket
   неизвестен, остановись с одним коротким вопросом.
2. Получи явный номер PR. Не угадывай его по активной ветке.
3. Прочитай PRD, plan, tasklist, feedback и существующий review по протоколу
   AIDD, затем project/path rules.
4. Проверь наличие `tools/scripts/download-sonar-issues.os`,
   `sonar-project.properties`, `oscript` и env var `SONAR_TOKEN`. Не выводи
   значение токена.
5. Запусти из корня проекта:

   ```text
   oscript tools/scripts/download-sonar-issues.os -pr <PR>
   ```

6. Прочитай `out/sonar-reports/issues-pr-<PR>.json` и проверь:
   - JSON корректен;
   - `total` равен фактическому количеству элементов `issues`;
   - поле `pullRequest`, если присутствует, соответствует запрошенному PR;
   - у issue есть `key`, `rule`, `message`, `component` и однозначная
     file-level или line/textRange location.
   При неполной выгрузке не анализируй усеченный список.
7. Сопоставь `component` с repo-relative путем и прочитай точный исходник и
   релевантный фрагмент diff. Если сопоставление неоднозначно, зафиксируй
   `BLOCKED`, не угадывай файл.
8. Сгруппируй issues по общей причине и решению. Приоритизируй подтвержденные
   `BUG`, `VULNERABILITY`, `BLOCKER` и `CRITICAL`, но не подменяй анализ одной
   severity.
9. Для каждой независимой группы создай или обнови `RV-XXX` в
   `aidd/docs/review/<ticket>.md`. Повторный запуск сопоставляй сначала по
   Sonar issue keys и не создавай дубликаты. Если key изменился, используй
   rule, component, hash/message и location только как кандидаты на
   сопоставление и подтверди их исходником.
10. Покажи пользователю группы решений. Один ответ может принять или отклонить
    несколько явно перечисленных `RV-XXX`; не спрашивай разрешение по каждому
    Sonar issue отдельно.
11. Подтвержденное обоснованное исключение фиксируй как `Decision: DECLINED` с
    причиной. Не спрашивай о нем повторно, пока evidence и project rules не
    изменились. Sonar status при этом остается без изменений.
12. Для принятых `FIX_CANDIDATE` последовательно используй
    `.claude/skills/aidd-fix-review/SKILL.md`, один `RV-XXX` за запуск.
13. `RULE_CONFIGURATION_CANDIDATE` не исправляй через `aidd-fix-review`:
    изменение project config или quality profile требует отдельного явно
    согласованного scope.
14. Выполни релевантную локальную проверку. Статус `FIXED` означает только, что
    локальное исправление внесено и проверено; до нового Sonar-анализа оставь
    `Sonar verification: PENDING_RESCAN`.
15. Перед обновлением `Sonar verification` докажи, что после исправления
    завершился новый Sonar-анализ нужного PR и revision. Используй доступное
    evidence: pipeline/job, analysis time или analyzed revision. Запиши его в
    `Sonar analysis evidence`. Сам факт повторного скачивания JSON не
    подтверждает свежесть анализа.
16. После подтвержденного свежего анализа обнови `Sonar verification`:
    - `NOT_REPORTED` — связанные keys или подтвержденные им эквиваленты
      отсутствуют;
    - `STILL_OPEN` — issue продолжает возвращаться;
    - `PENDING_RESCAN` — свежий анализ после изменения не подтвержден.

## Формат записи review

Используй одну запись на независимую причину:

```markdown
### RV-XXX — Sonar: <краткая причина>

- Status: OPEN
- Category: <blocking|important|minor>
- Source: SonarQube
- PR: <number>
- Sonar issues: <key, ...>
- Rules: <rule, ...>
- Location: <repo-relative path[:line]>
- Evidence: <что подтверждено в коде/diff/rules>
- Classification: <FIX_CANDIDATE|JUSTIFIED_EXCEPTION_CANDIDATE|RULE_CONFIGURATION_CANDIDATE|BLOCKED>
- Recommendation: <исправление, исключение или настройка правила>
- Decision: <ACCEPTED|DECLINED|пусто>
- Actual fix:
- Sonar analysis evidence: <pipeline/job, analysis time или revision>
- Sonar verification: <PENDING_RESCAN|NOT_REPORTED|STILL_OPEN>
```

Не переписывай исходную evidence и recommendation задним числом. Фактическое
исправление и результат повторной проверки дополняй отдельными полями.

## Результат

Сообщи номер PR, число полученных issues и групп, созданные/обновленные
`RV-XXX`, принятые исключения, blockers и следующий шаг. Отдельно напомни, что
статусы SonarQube не изменялись.
