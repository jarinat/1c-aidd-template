---
name: aidd-commit-block
description: >
  Один commit текущего change-блока в рамках AIDD. Используй для сценария
  commit-block: определить commit ticket, собрать короткое сообщение и выполнить
  commit через `.claude/scripts/commit-block.sh`.
---

# AIDD Commit Block

Этот skill предназначен для основной сессии. Он не запускает subagent и не
обновляет `tasklist`.

Source of truth:

- общая политика git и commit по change-блокам:
  - `.claude/rules/core/git-workflow.md`
- project ticketing:
  - `.claude/rules/project/ticketing.md`
- механизм commit:
  - `.claude/scripts/commit-block.sh`

## Критически важно

- Используй точно команду `bash .claude/scripts/commit-block.sh ...`
- Не используй heredoc, `$(cat ...)`, временные message-файлы и составные
  команды вида `cd ... && git add ... && git commit ...`
- Default staged paths определяются проектным `.claude/scripts/commit-block.sh`
  и `.claude/rules/project/ticketing.md`; не считай `src/` универсальным
  default для всех проектов.
- Если нужно добавить другой путь, передавай его отдельным аргументом
  `--add-path`

## Алгоритм

1. Определи ticket id: используй переданный аргумент или `aidd/docs/.active_ticket`.
2. Определи commit ticket:
   - сверь допустимый формат с `.claude/rules/project/ticketing.md`;
   - если активный ticket id является work ticket с локальным суффиксом
     подтикета, используй для commit базовый commit ticket без суффикса по
     правилам `.claude/rules/project/ticketing.md`;
   - если активный тикет уже подходит для commit, используй его;
   - если нужно отдельное значение и оно передано аргументом, используй его;
   - если commit ticket определить нельзя, остановись и попроси пользователя
     указать его.
3. Прочитай `aidd/docs/tasklist/<ticket>.md`, если файл существует, и определи
   текущий change-блок:
   - если передан аргумент с названием блока, используй его как подсказку;
   - иначе опирайся на текущие изменения в project default staged paths и
     ближайший незакрытый блок.
4. Прочитай diff по project default staged paths и дополнительным путям,
   которые относятся к текущему блоку, затем кратко суммируй фактические
   изменения блока.
5. Сформируй commit message:
   - используй активный commit subject format из
     `.claude/rules/project/ticketing.md`;
   - subject должен быть не длиннее 50 символов целиком;
   - subject должен быть понятен без AIDD-артефактов и не должен включать
     локальный work ticket с суффиксом подтикета или фразы вроде `Блок 2`;
   - body: 2-6 отдельных строк с ключевыми изменениями блока
6. Выполни commit только так:

```bash
bash .claude/scripts/commit-block.sh "<subject по project ticketing rules>" \
  --body-line "Изменение 1" \
  --body-line "Изменение 2"
```

7. В ответе покажи итоговый subject и кратко перечисли, что вошло в commit.
