---
name: project-onboarding
description: >
  Обследовать локальный 1С/EDT проект после установки шаблона и заполнить
  project-specific правила без догадок: profile, ticketing, naming,
  change-policy, testing, pitfalls и path rules.
---

# Project Onboarding

Используй этот skill, когда пользователь просит настроить проект под AIDD,
донастроить локальный шаблон, обследовать новый 1С/EDT проект или заполнить
project rules.

## Source of truth

Основной сценарий находится в:

```text
.claude/docs/onboarding-project.md
```

Сначала прочитай этот документ и следуй ему. Этот `SKILL.md` является
Claude-входом в общий сценарий, а не отдельным вторым набором правил.

## Обязательные ограничения

- Не меняй бизнес-код в `src/`.
- Не запускай `rlm-bsl-index build/update` без явного подтверждения.
- Не добавляй `.claude/`, `aidd/` или `AGENTS.md` в Git ignore/exclude без
  явной просьбы.
- Не копируй project policy из другого проекта механически.
- Отделяй факты, кандидаты и вопросы.

## Результат

После подтверждения пользователя заполни или обнови:

- `.claude/rules/project/profile.md`;
- `.claude/rules/project/ticketing.md`;
- `.claude/rules/project/naming.md`;
- `.claude/rules/project/change-policy.md`;
- `.claude/rules/project/testing.md`;
- `.claude/rules/project/pitfalls.md`;
- `.claude/rules/project/onboarding-status.md`;
- `.claude/rules/paths/*.md`.
