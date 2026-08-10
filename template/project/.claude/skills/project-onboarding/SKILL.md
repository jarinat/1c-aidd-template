---
name: project-onboarding
description: >
  Обследовать локальный 1С/EDT проект и заполнить project-specific правила
  личного слоя: profile, ticketing, naming, change-policy, testing, pitfalls и
  path rules. Надстройка над корпоративным skill mpl-project-onboarding.
---

# Project Onboarding (надстройка над `mpl-project-onboarding`)

Сам порядок обследования, разделение на подтверждённые факты, допущения,
открытые вопросы и решения человека, а также запрет менять `src/` и коммитить
задаёт корпоративный skill **`mpl-project-onboarding`**. Прочитай его и следуй
ему; здесь описана только дельта личного AIDD-слоя.

## Дельта личного слоя

**Расширенный сценарий обследования.** Личный слой несёт подробный сценарий с
вопросами и порядком разбора:

```text
.claude/docs/onboarding-project.md
```

Читай его после корпоративного skill — он не отменяет корпоративные корзины
вывода, а детализирует шаги.

**Другое место материализации.** Корпоративный skill по умолчанию пишет
`doc/ai/project/project-rules.md`. В проекте с этим личным слоем подтверждённые
правила вместо этого раскладываются по файлам:

- `.claude/rules/project/profile.md`;
- `.claude/rules/project/ticketing.md`;
- `.claude/rules/project/naming.md`;
- `.claude/rules/project/change-policy.md`;
- `.claude/rules/project/testing.md`;
- `.claude/rules/project/pitfalls.md`;
- `.claude/rules/project/onboarding-status.md`;
- `.claude/rules/paths/*.md`.

Два места хранения проектного слоя — известное расхождение, оно разбирается
отдельно. До его разрешения в проекте с личным слоем пиши в
`.claude/rules/project/*`, а `doc/ai/project/project-rules.md` не создавай без
явной просьбы.

**Материализация только после подтверждения пользователя** — как и в
корпоративном skill. Дополнительно не добавляй `.claude/`, `aidd/` или
`CLAUDE.local.md` в Git ignore/exclude без явной просьбы и не запускай
построение локальных индексов без подтверждения.
