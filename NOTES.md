# Что было не так и чего не хватает

Разбор по состоянию на август 2026, после интеграции плагина в игру «Морской бой».
Верхняя часть — уже исправлено в этом репозитории, нижняя — то, что осталось.

## Обновление SDK (v0.2.0)

- **Android:** `io.appmetrica.analytics:analytics` 7.14.1 → **8.5.0**. Это не
  косметика: Yandex Mobile Ads 8.x требует AppMetrica 8.3.0+ в пределах одной
  мажорной версии, а игра использует оба SDK сразу. На 7.x сборка с рекламой
  8.x конфликтует. API `AppMetricaConfig`/`AppMetrica.activate` не изменился.
- **iOS:** под `AppMetricaAnalytics ~> 5.0` заменён на `AppMetricaCore ~> 6.5`.
  Причины две. Первая — зонтичный `AppMetricaAnalytics` тянет полдюжины
  подов, а Swift-коду нужен только `AppMetricaCore`. Вторая важнее:
  `AppMetricaAnalytics 6.6.0` прибивает `AppMetricaCore = 6.6.0`, тогда как
  `YandexMobileAds 8.3.0` требует `AppMetricaCore ~> 6.5.0` (то есть < 6.6) —
  вместе они не разрешаются, и `pod install` падает.
- `compileSdk`/`targetSdk` подняты до 36, `minSdk` до 21 — требования
  соседнего рекламного SDK и текущих правил Google Play.
- **Podspec переименован** в `CapacitorAppMetrica.podspec`. Capacitor выводит
  имя пода из имени пакета (`capacitor-app-metrica` → `CapacitorAppMetrica`) и
  генерирует в Podfile именно его; при прежнем имени `AppMetrica.podspec`
  команда `pod install` падала с «No podspec found». Заодно ушло затенение типа
  `AppMetrica` из самого SDK.

Android-часть скомпилирована и упакована в APK на 8.5.0. iOS не собирался.

## Исправлено ранее

### 1. Не было iOS-реализации вообще — критично

`package.json` объявлял `capacitor.ios.src = "ios"`, а `AppMetrica.podspec`
собирал `ios/Plugin/**/*.{swift,h,m,...}` — но самой папки `ios/` в репозитории
не было. Последствия:

- `npx cap sync ios` обрывался с `ENOENT: scandir .../capacitor-app-metrica/ios`
  и **не доходил до записи списка плагинов** — то есть ломал синхронизацию всего
  проекта, а не только этого плагина;
- даже если обойти обрыв, pod собирался пустым, и любой вызов на iOS падал с
  «plugin not implemented».

Добавлены `ios/Plugin/AppMetricaPlugin.swift` и `ios/Plugin/AppMetricaPlugin.m`
с теми же четырьмя методами и **теми же именами параметров**, что на Android
(в частности `userProfileID`, а не `profileID`).

### 2. Android терял параметры событий

`reportEvent` собирал параметры через `params.getString(key)`. Этот метод
возвращает `null` для чисел, булевых значений и вложенных объектов, поэтому
событие вида `{ level: 5, win: true }` уходило в AppMetrica с пустыми
значениями. Теперь значения приводятся к строке через `opt(key)` —
как и в добавленной iOS-версии.

### 3. Метаданные пакета

- `repository.url` указывал на `github.com/nickolasgeno/capacitor-app-metrica`
  (upstream, от которого форкнуто), а не на актуальный репозиторий.
- В `files` заявлен `dist/`, но он в `.gitignore`, а собирался только скриптом
  `prepublishOnly`, который при установке из git-ссылки **не запускается**.
  Пакет приезжал без JS, и приходилось объявлять плагин вручную через
  `registerPlugin('AppMetrica')`. Добавлен скрипт `prepare` — npm запускает его
  при установке из git.

## Чего не хватает

### Проверка сборки

**Swift-код ещё ни разу не компилировался** — нужен macOS: `pod install` плюс
сборка в Xcode. Сигнатуры сверены с публичными заголовками AppMetrica 6.5.1
(`AMAAppMetrica.h`), но проверка компилятором всё равно обязательна.

Отдельно: в `package.json` нет скрипта `verify:ios`, поэтому даже локальный
`npm run verify` не собирает iOS-часть — до первой сборки в Xcode ошибки в ней
никто не поймает.

### Пробелы в API

Плагин закрывает только четыре метода. Для полноценной аналитики обычно нужны:

- `reportError(name, error)` / `reportCrash` — сейчас ошибки никак не отправить;
- `sendEventsBuffer()` — принудительная отправка перед выходом из приложения;
- `pauseSession()` / `resumeSession()`;
- `setLocation()` / `setLocationTracking()`;
- профиль пользователя (`UserProfile` с атрибутами), а не только его id;
- отправка покупок (`reportRevenue`) — понадобится, когда подключится биллинг;
- `putErrorEnvironment` / `putAppEnvironment` — контекст для расследования сбоев.

### Прочее

- **Конфигурация инициализации жёстко минимальная.** `AppMetricaConfig` строится
  только из ключа: нельзя включить `logs`, задать `sessionTimeout`,
  `crashReporting`, `appVersion`. Для отладки логи особенно полезны.
- **`InitOptions` не позволяет отложить сбор данных** (`dataSendingEnabled`),
  а это нужно, если приложению требуется согласие пользователя до старта
  аналитики.
- **Нет тестов и demo-проекта** (в соседнем `capacitor-yandex-ads` demo есть).
- **README короткий**: показывает только ручной `registerPlugin` — после
  появления `dist/` его стоит переписать на обычный импорт из пакета.
