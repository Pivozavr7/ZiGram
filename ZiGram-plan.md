# ZiGram: план v2 (готовый libtdjson, без сборки TDLib)

Заменяет раздел про установку TDLib из первого концепта. Всё остальное (Zig + Dear ImGui + SDL3 GPU, Linux, Apache-2.0, MVP 0 = ядро, MVP 1 = интерфейс) остаётся.

## 1. Что поменялось

| Было | Стало |
|---|---|
| TDLib из пакета Arch/AUR (сборка) | Готовый `libtdjson.so` из `@prebuilt-tdlib/linux-x64-glibc` |
| `@cImport` заголовка `td_json_client.h` | Свои `extern`-объявления, заголовок не нужен |
| Линковка при сборке | **Загрузка через `std.DynLib`** (путь настраивается) |
| Версия «какая в репе» | Закреплённая: **1.8.70** (npm `0.1008070.0`) |

Бинарник слинкован статически с OpenSSL и zlib, так что системных зависимостей TDLib не добавляет. Собирать самому ничего не нужно, и твоему ПК это по силам: тяжёлого C++ у нас только Dear ImGui, он собирается быстро.

## 2. Как хранить и получать libtdjson

**Бинарник в git не коммитим** (десятки МБ, чужой артефакт). Репозиторий содержит только скрипт и хэш.

```
ZiGram/
├── vendor/
│   ├── tdlib/                 # в .gitignore, сюда скачивается .so
│   └── tdlib.lock             # версия + sha256 (в git)
└── scripts/
    └── fetch-tdlib.sh
```

`scripts/fetch-tdlib.sh` (логика):

1. Прочитать версию и `sha256` из `tdlib.lock`
2. `npm pack @prebuilt-tdlib/linux-x64-glibc@<версия>` во временную папку
3. Распаковать, взять `libtdjson.so`
4. Сверить `sha256sum` с lock-файлом, при несовпадении остановиться
5. Положить в `vendor/tdlib/` вместе с текстом лицензии TDLib (Boost)

Хэш для lock-файла берётся один раз с твоего уже скачанного файла: `sha256sum libtdjson.so`.

Позже можно заменить npm на прямую загрузку из GitHub Releases, интерфейс скрипта останется тем же.

## 3. Загрузка библиотеки в Zig

`td.zig` открывает `.so` через `std.DynLib` и заполняет таблицу указателей:

```zig
pub const Api = struct {
    create_client_id: *const fn () callconv(.c) c_int,
    send: *const fn (c_int, [*:0]const u8) callconv(.c) void,
    receive: *const fn (f64) callconv(.c) ?[*:0]const u8,
    execute: *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8,
};
```

Порядок поиска библиотеки:

1. `tdlib_path` из конфига ZiGram
2. `$ZIGRAM_TDLIB` (переменная окружения)
3. `vendor/tdlib/libtdjson.so` рядом с проектом/бинарником
4. `~/.local/share/zigram/libtdjson.so`
5. Системная (`telegram-tdlib` из AUR, если кто-то её поставил)

Плюсы: `build.zig` не зависит от наличия TDLib, можно тестировать ядро на подменном `.so`, пользователь может подставить свою версию. Если ни одна не нашлась, понятная ошибка с подсказкой «запусти `scripts/fetch-tdlib.sh`».

Проверка при старте: `td_execute({"@type":"getOption","name":"version"})` и сравнение с ожидаемой версией (предупреждение, если отличается).

## 4. Роадмап

### MVP 0: ядро без GUI

**0.0 Каркас**
- [ ] `build.zig`, `build.zig.zon` (зафиксировать версию Zig)
- [ ] `scripts/fetch-tdlib.sh`, `tdlib.lock`, `.gitignore`
- [ ] README: где взять `api_id`/`api_hash` (my.telegram.org), в репозиторий их не класть

**0.1 FFI**
- [ ] `td.zig`: DynLib, таблица функций, поиск библиотеки
- [ ] Проверка версии, `setLogVerbosityLevel`
- [ ] Поток-приёмник (`td_receive`) + потокобезопасная очередь событий
- [ ] `td_send` с `@extra` и сопоставление ответов с запросами

**0.2 Авторизация**
- [ ] Автомат состояний: `WaitTdlibParameters` → `WaitPhoneNumber` → `WaitCode` → `WaitPassword` → `Ready`
- [ ] Конфиг `.zon`: `api_id`, `api_hash`, директории данных
- [ ] `zigram-cli login`

**0.3 Данные**
- [ ] Модели: `User`, `Chat`, `Message`, `File`
- [ ] Обработка `updateNewChat`, `updateChatLastMessage`, `updateChatPosition`, `updateNewMessage`, `updateMessageContent`
- [ ] Список чатов с пагинацией (`loadChats`)
- [ ] История (`getChatHistory`)

**0.4 Действия**
- [ ] `sendMessage`, ответ, редактирование, удаление
- [ ] `viewMessages`, typing, статусы
- [ ] `downloadFile` + `updateFile` (фото)
- [ ] Тесты: парсер JSON, автомат, очередь (`zig build test`)

**Критерий готовности MVP 0:** `zigram-cli` логинится, показывает чаты, читает историю, отправляет и принимает сообщения в реальном времени.

### MVP 1: интерфейс

**0.5 Окно** — SDL3 + SDL_GPU + Dear ImGui, шрифты (кириллица, CJK, emoji), HiDPI на Wayland
**0.6 Переписка** — список чатов, виртуальный скролл (clipper), пузыри, ввод, IME
**0.7 Темы и конфиг** — MD3, Linear, Flat; хоткеи; всё в `.zon`
**0.8 Системное** — D-Bus уведомления, счётчики, mute, поиск
**0.9 Медиа** — фото, стикеры (webp/webm), голосовые, кружки, GIF; tgs в последнюю очередь
**0.10 Мультичат** — несколько чатов одновременно
**1.0 Юзабельная версия** — только после неё публикация на GitHub и, при желании, AUR-пакет `zigram-git`

## 5. Риски (новые и старые)

- **Чужой бинарник:** хэш в lock-файле + provenance npm-пакета. Для релизов ZiGram позже разумно предложить также вариант с системным TDLib.
- **glibc:** сборка требует glibc ≥ 2.22, на Arch не проблема.
- **Версия TDLib:** JSON-интерфейс стабилен, но поля меняются. Парсер писать терпимым к неизвестным полям (`ignore_unknown_fields`).
- **ImGui и текст:** IME, emoji, RTL проверять рано. RTL ImGui не поддерживает.
- **Нестабильность Zig:** версия зафиксирована в `build.zig.zon`.
- **Лицензия:** TDLib под Boost (BSL-1.0), текст лицензии держим рядом с бинарником.

## 6. Ближайшие шаги

1. `sha256sum libtdjson.so` и заполнить `tdlib.lock`
2. Написать `fetch-tdlib.sh`
3. `td.zig`: DynLib + `td_execute` getOption version (первый «живой» вызов)
4. Поток-приёмник и автомат авторизации
