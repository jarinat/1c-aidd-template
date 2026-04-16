# REFERENCE — EDT формы 1С 8.3.25

Краткий справочник по структуре `Form.form` для задач с элементами формы.

## Полезные команды для анализа формы

Перед чтением файла в PowerShell выставляй UTF-8:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

Найти элемент, команду, обработчик:

```powershell
rg -n "<name>ИмяЭлемента</name>|Form.Command.ИмяКоманды|<event>|<name>ИмяОбработчика</name>" "src/.../Form.form" "src/.../Module.bsl"
```

После найденного якоря читай небольшой диапазон строк через `Read` с
offset/limit. Не используй `awk` или `sed` для нарезки `Form.form`, если это не
явный fallback после неудачного `Read`: такие команды могут вызвать лишний
permission-вопрос.

Вычислить максимальный `id` в форме:

```powershell
(Get-Content -Encoding UTF8 "src/.../Form.form" |
    Select-String "<id>" |
    ForEach-Object { [int]($_.Line -replace ".*<id>(-?\d+)</id>.*", '$1') } |
    Measure-Object -Maximum).Maximum
```

Найти все обращения к элементу формы:

```powershell
rg -n "Элементы\.ИмяЭлемента|Команды\.ИмяКоманды|Form\.Command\.ИмяКоманды" "src/.../Forms/ИмяФормы"
```

## Как устроен `Form.form`

Чаще всего в EDT-форме есть такие большие блоки:

- корневые `<items>` — дерево визуальных элементов формы
- `<autoCommandBar>` — командная панель формы
- `<handlers>` — обработчики событий формы
- `<attributes>` — реквизиты формы
- `<formCommands>` — команды формы
- `<commandInterface>` — интерфейс команд

## Типовые узлы

### 1. Поле формы

```xml
<items xsi:type="form:FormField">
  <name>ИмяЭлемента</name>
  <id>100</id>
  <visible>true</visible>
  <enabled>true</enabled>
  <userVisible>
    <common>true</common>
  </userVisible>
  <dataPath xsi:type="form:DataPath">
    <segments>Объект.Реквизит</segments>
  </dataPath>
  <titleLocation>None</titleLocation>
  <extendedTooltip>
    <name>ИмяЭлементаExtendedTooltip</name>
    <id>101</id>
    <type>Label</type>
    <autoMaxWidth>true</autoMaxWidth>
    <autoMaxHeight>true</autoMaxHeight>
    <extInfo xsi:type="form:LabelDecorationExtInfo">
      <horizontalAlign>Left</horizontalAlign>
    </extInfo>
  </extendedTooltip>
  <contextMenu>
    <name>ИмяЭлементаКонтекстноеМеню</name>
    <id>102</id>
    <autoFill>true</autoFill>
  </contextMenu>
  <type>InputField</type>
  <editMode>Enter</editMode>
  <showInHeader>true</showInHeader>
  <showInFooter>true</showInFooter>
  <extInfo xsi:type="form:InputFieldExtInfo">
    <width>20</width>
    <height>1</height>
    <horizontalStretch>false</horizontalStretch>
    <verticalStretch>false</verticalStretch>
    <chooseType>true</chooseType>
    <typeDomainEnabled>true</typeDomainEnabled>
    <textEdit>true</textEdit>
  </extInfo>
</items>
```

Замечания:

- `type` определяет тип визуального элемента: `InputField`,
  `HTMLDocumentField` и т.д.
- размеры и растяжение чаще лежат в `extInfo`
- для многострочных полей часто используются `height`, `wrap`, `multiLine`

### 2. Группа формы

```xml
<items xsi:type="form:FormGroup">
  <name>ГруппаОсновная</name>
  <id>200</id>

  <items xsi:type="form:FormField">
    ...
  </items>

  <visible>true</visible>
  <enabled>true</enabled>
  <userVisible>
    <common>true</common>
  </userVisible>
  <title>
    <key>ru</key>
    <value>Группа основная</value>
  </title>
  <extendedTooltip>
    ...
  </extendedTooltip>
  <type>UsualGroup</type>
  <extInfo xsi:type="form:UsualGroupExtInfo">
    <group>Vertical</group>
    <showLeftMargin>true</showLeftMargin>
    <throughAlign>Auto</throughAlign>
    <currentRowUse>Auto</currentRowUse>
  </extInfo>
</items>
```

Замечания:

- у группы дочерние `<items>` идут внутри самой группы
- тип группы может быть `UsualGroup`, `Page`, `Pages`, `ColumnGroup`,
  `CommandBar`
- для страничных контейнеров ищи локальный образец в проекте и повторяй его
  структуру, а не придумывай вручную

### 3. Таблица и её колонки

```xml
<items xsi:type="form:Table">
  <name>ТаблицаЭлементов</name>
  <id>300</id>
  <visible>true</visible>
  <enabled>true</enabled>
  <dataPath xsi:type="form:DataPath">
    <segments>ТаблицаЭлементов</segments>
  </dataPath>

  <items xsi:type="form:FormGroup">
    <name>ТаблицаЭлементовКолонка</name>
    <id>301</id>
    <items xsi:type="form:FormField">
      ...
    </items>
    <type>ColumnGroup</type>
    <extInfo xsi:type="form:ColumnGroupExtInfo">
      <group>InCell</group>
      <showTitle>true</showTitle>
    </extInfo>
  </items>

  <commandBarLocation>None</commandBarLocation>
  <autoCommandBar>
    <name>ТаблицаЭлементовКоманднаяПанель</name>
    <id>302</id>
    <horizontalAlign>Left</horizontalAlign>
  </autoCommandBar>

  <handlers>
    <event>BeforeAddRow</event>
    <name>ТаблицаЭлементовПередНачаломДобавления</name>
  </handlers>
  <handlers>
    <event>BeforeDeleteRow</event>
    <name>ТаблицаЭлементовПередУдалением</name>
  </handlers>

  <searchStringAddition>
    ...
  </searchStringAddition>
  <viewStatusAddition>
    ...
  </viewStatusAddition>
  <searchControlAddition>
    ...
  </searchControlAddition>

  <contextMenu>
    ...
  </contextMenu>
</items>
```

Замечания:

- у таблицы часто есть собственные additions поиска и просмотра
- колонки таблицы обычно оформлены как `form:FormGroup` с типом `ColumnGroup`
- если пользователь просит "добавить колонку", ищи существующую колонку этой же
  таблицы и копируй её структуру

### 4. Кнопка в командной панели или контекстном меню

```xml
<items xsi:type="form:Button">
  <name>КомандаСохранить</name>
  <id>400</id>
  <visible>true</visible>
  <enabled>true</enabled>
  <userVisible>
    <common>true</common>
  </userVisible>
  <extendedTooltip>
    ...
  </extendedTooltip>
  <commandName>Form.Command.Сохранить</commandName>
  <representation>Auto</representation>
  <autoMaxWidth>true</autoMaxWidth>
  <autoMaxHeight>true</autoMaxHeight>
  <placementArea>UserCmds</placementArea>
  <representationInContextMenu>Auto</representationInContextMenu>
</items>
```

Замечания:

- кнопка обычно не живёт сама по себе: ей нужна команда в `<formCommands>` или
  существующая стандартная команда
- в контекстном меню кнопки часто вложены в группу-кнопкогруппу

### 5. Команда формы

```xml
<formCommands>
  <name>Сохранить</name>
  <title>
    <key>ru</key>
    <value>Сохранить</value>
  </title>
  <id>500</id>
  <toolTip>
    <key>ru</key>
    <value>Сохранить</value>
  </toolTip>
  <use>
    <common>true</common>
  </use>
  <action xsi:type="form:FormCommandHandlerContainer">
    <handler>
      <name>Сохранить</name>
    </handler>
  </action>
  <currentRowUse>DontUse</currentRowUse>
</formCommands>
```

Если добавил новую команду, проверь:

- есть ли кнопка, которая на неё ссылается
- есть ли обработчик в `Module.bsl`
- не проще ли использовать стандартную команду существующего элемента

### 6. Реквизит формы

```xml
<attributes>
  <name>ИмяРеквизитаФормы</name>
  <title>
    <key>ru</key>
    <value>Имя реквизита формы</value>
  </title>
  <id>600</id>
  <valueType>
    <types>String</types>
    <stringQualifiers/>
  </valueType>
  <view>
    <common>true</common>
  </view>
  <edit>
    <common>true</common>
  </edit>
</attributes>
```

Создавай новый реквизит формы, если:

- элемент связан не с `Объект.<...>`, а с временными данными формы
- нужен отдельный буфер значений формы
- нужен источник для HTML, дерева, вычисляемого представления и т.д.

## Что обычно меняется при типовых задачах

### Добавить элемент на форму

1. Найти правильный контейнер.
2. Найти соседний похожий элемент.
3. Скопировать его структуру.
4. Поменять:
   - `name`
   - `id`
   - `dataPath`
   - `title`
   - `type`
   - нужные свойства в `extInfo`
5. При необходимости добавить реквизит формы и код в `Module.bsl`.

### Изменить видимость, доступность, размеры

Если свойство постоянное:

- `visible`
- `enabled`
- `width`
- `height`
- `horizontalStretch`
- `verticalStretch`

Если свойство зависит от условий, используй код формы:

```1c
Элементы.ИмяЭлемента.Видимость = Ложь;
Элементы.ИмяЭлемента.Доступность = Ложь;
```

### Удалить элемент

1. Удалить XML-узел элемента из правильного контейнера.
2. Проверить ссылки на элемент в `Module.bsl`.
3. Проверить, не осталось ли:
   - обработчиков по имени элемента
   - команд формы, которые были нужны только ему
   - обращений из адаптации мобильной формы, инициализации, заполнения данных

## Важные правила безопасности

- Не придумывай новые теги, если их нет в локальных образцах.
- Не меняй структуру `autoCommandBar`, `contextMenu`, `Pages`, `ColumnGroup`,
  если не проверил соседний рабочий пример.
- Не удаляй обработчик из `Module.bsl`, пока не убедишься, что он больше нигде
  не используется.
- Если задача звучит как "скрыть элемент", сначала реши, это дизайн-настройка
  или условная логика во время работы формы.
