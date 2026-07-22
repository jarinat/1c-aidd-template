# Каталог сценариев v1.1

## Read-only

1. Discovery workspace и точного projectName.
2. Details неизменяемого metadata object.
3. Чтение BSL method по FQN и строкам.
4. References/callers выбранного method.
5. Structure управляемой формы.
6. Query validation; отдельно зафиксировать project-aware или syntax-only режим.

## Write fixtures

Все имена получают уникальный benchmark prefix и различаются для серверов.

1. Create server-only CommonModule; assert contexts.
2. Add one exported method; assert exact source.
3. Modify literal в существующем method; assert stale-safe read-before-write.
4. Add method с текстом query; assert сохранность существующего метода.
5. Modify query и validate итоговый query.
6. Create DataProcessor.
7. Create managed form.
8. Add form String attribute.
9. Add bound input field — отдельный сценарий от attribute.
10. Typed cleanup CommonModule и DataProcessor; assert отсутствие fixtures.

## Expected evidence

| Область | Минимальная проверка |
|---|---|
| CommonModule | имя, server-only context, отсутствие лишних contexts |
| BSL | exact method/literal, отсутствие лишних изменений |
| Query | итоговый текст и validation evidence |
| Form | String value type, attribute и bound FormField |
| Cleanup | объект отсутствует в metadata и в source |

Unsupported capability — `UNSUPPORTED`, а не «медленный» или «failed» run.
