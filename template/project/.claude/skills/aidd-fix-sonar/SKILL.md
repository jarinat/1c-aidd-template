---
name: aidd-fix-sonar
description: >
  Разбор и исправление замечаний SonarQube для конкретного Pull Request в
  1С/EDT проекте. Используй, когда пользователь просит скачать, проверить,
  сгруппировать или исправить Sonar issues указанного PR с фиксацией решений в
  AIDD review. SonarQube в этом сценарии используется только для чтения.
---

# AIDD Fix Sonar

Отчёт Sonar получай только корпоративным skill `mpl-sonar-evidence`: он
единственный получатель отчёта и он же возвращает coverage. Сохраняй инженерные
решения в
`aidd/docs/review/<ticket>.md` и применяй принятые исправления через
`.claude/skills/aidd-fix-review/SKILL.md`.

Source of truth:

- проверка issue по коду и критерии решения: `mpl-fix-sonar`
  (`.agents/skills/mpl-fix-sonar/SKILL.md`) — разделение фаз «собрать
  свидетельства» и «исправить», вердикты по каждой issue, дисциплина
  группировки, критерии по длине строки и смешению алфавитов. Здесь эта
  процедура не повторяется;
- lifecycle review: `.claude/rules/core/aidd-workflow.md` и
  `.claude/rules/core/aidd-artifacts.md`;
- политика review: `.claude/rules/core/code-review.md`;
- выбор инструментов: `.claude/rules/core/tool-usage.md`;
- project-specific исключения: `.claude/rules/project/*.md` и
  `.claude/rules/paths/*.md`;
- исправление принятого `RV-XXX`:
  `.claude/skills/aidd-fix-review/SKILL.md`.
- общий read-only contract выгрузки, JSON validation и coverage:
  корпоративный skill `mpl-sonar-evidence`.

## Границы

- Один запуск работает только с одним явно указанным PR.
- SonarQube используется read-only: не меняй статусы issues, assignee, tags,
  comments, quality profile или параметры правил через API.
- Не считай Sonar issue безусловной командой на изменение кода. Проверяй
  правило, точный исходник, diff PR и project-specific правила.
- Не вшивай в skill префиксы, имена объектов и исключения отдельного проекта.
- Не считай этот сценарий полным AIDD review изменений: он импортирует и
  обрабатывает только Sonar-находки.
- Не запускай этот workflow из `mpl-review-mr`: review MR получает только
  evidence и не создаёт `RV-XXX`, решения или исправления.
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

Эти четыре значения — словарь записи `RV-XXX`, а не отдельные критерии. Сами
критерии — по каким признакам issue подтверждается, отклоняется, уходит в
конфигурацию правила или к человеку, как группировать issues и как разбирать
длину строки и смешение алфавитов — берутся из `mpl-fix-sonar` и здесь не
повторяются. Соответствие вердиктов: подтверждено -> `FIX_CANDIDATE`, требует
решения или обоснованное отклонение -> `JUSTIFIED_EXCEPTION_CANDIDATE`,
конфигурация правила -> `RULE_CONFIGURATION_CANDIDATE`, недоступен источник или
контекст -> `BLOCKED`.

Project-specific соглашения именования, на которые опирается разбор смешения
алфавитов, лежат в `.claude/rules/project/naming.md` и применимых path rules.

## Алгоритм

1. Определи ticket id из аргумента или `aidd/docs/.active_ticket`. Если ticket
   неизвестен, остановись с одним коротким вопросом.
2. Получи явный номер PR. Не угадывай его по активной ветке.
3. Прочитай PRD, plan, tasklist, feedback и существующий review по протоколу
   AIDD, затем project/path rules.
4. Получи отчёт через корпоративный skill `mpl-sonar-evidence`, передав ему
   номер PR, головную ревизию и каталог результата вне рабочего дерева. Свой
   вызов helper-а не собирай: у отчёта один получатель.
5. Возьми путь отчёта и coverage ровно такими, какими их вернул
   `mpl-sonar-evidence`. При `unavailable`, `incomplete` и `stale` данные Sonar
   не анализируй вовсе; при `unverified` считай их подсказками, которые обязан
   подтвердить исходником, и не выдавай за подтверждённый `Source: SonarQube`.
6. Прочитай отчёт по возвращённому пути. Evidence revision сохраняй для
   последующего rescan, но не подменяй им отдельное подтверждение свежего
   анализа после исправлений.
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
