---
paths:
  - "<source-path>/**"
---
# Правила для `<source-path>`

Этот path-scoped rule применяется к указанной зоне репозитория.

- Опиши назначение зоны.
- Укажи тип зоны: `active-edt-source`, `legacy-designer-dump`,
  `extension-source`, `test-extension`, `external-epf-erf`,
  `smoke-bdd-tests`, `generated-build-output`, `readonly-vendor` или другой
  подтвержденный тип.
- Укажи, является ли зона source of truth для разработки.
- Укажи, является ли она основной зоной изменений по умолчанию.
- Укажи ограничения на прямые изменения.
- Укажи связанные project rules, если для этой зоны важны naming, testing или
  change policy.
