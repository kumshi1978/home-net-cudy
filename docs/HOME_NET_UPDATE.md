# HOME NET stable-release updater

`home-net-update` обновляет весь HOME NET bundle из опубликованного GitHub
Release `kumshi1978/home-net-cudy`. Он не заменяет и не удаляет существующий
компонентный `podkop-awg-update`.

Оба updater пока существуют параллельно и имеют независимые config/state/lock.
Bundle installer сохраняет текущий `AUTO_UPDATE_MODE` компонентного updater,
если оператор явно не передал `HOME_NET_AUTO_UPDATE_MODE`. Его код и release
channel верхнеуровневый updater не изменяет.

## Файлы на роутере

```text
/usr/bin/home-net-update
/etc/init.d/home-net-update
/etc/home-net-update.conf
/etc/home-net-update.state
```

`/etc/home-net-update.state` хранит установленную версию HOME NET bundle отдельно
от версии failover:

```text
INSTALLED_BUNDLE_VERSION='1.5.2'
INSTALLED_BUNDLE_TAG='v1.5.2'
INSTALLED_AT='2026-10-04 12:00:00'
INSTALL_SOURCE='stable-release'
```

## Источник обновления

Updater обращается к GitHub Releases API и принимает release только если:

- `draft=false`;
- `prerelease=false`;
- tag строго соответствует `vX.Y.Z`;
- release новее установленной bundle version;
- `VERSION` и `HOME_NET_BUNDLE_VERSION` в `bundle.conf` совпадают с tag.

`install-all.sh` скачивается строго из принятого release tag и запускается с:

```sh
HOME_NET_BUNDLE_REF="$release_tag"
```

Moving-ветка `main` updater-ом не используется.

## Режимы

Ручная проверка без изменений:

```sh
/usr/bin/home-net-update check
```

Ручное применение на canary:

```sh
/usr/bin/home-net-update apply
```

Периодический procd-сервис запускает:

```sh
/usr/bin/home-net-update daemon
```

## Конфигурация

Значения по умолчанию:

```text
HOME_NET_UPDATE_MODE='check'
HOME_NET_UPDATE_CANARY='0'
HOME_NET_UPDATE_INTERVAL='86400'
HOME_NET_UPDATE_JITTER='21600'
HOME_NET_UPDATE_STARTUP_DELAY='300'
HOME_NET_UPDATE_COMMAND_TIMEOUT='120'
HOME_NET_UPDATE_HEALTH_TIMEOUT='600'
HOME_NET_UPDATE_HEALTH_RETRY_INTERVAL='10'
```

Существующий `/etc/home-net-update.conf` при повторной установке не
перезаписывается.

## Canary и fleet rollout

Автоматический `apply` сначала разрешается только на одном canary-router. Для
этого в его конфигурации должны одновременно присутствовать:

```text
HOME_NET_UPDATE_MODE='apply'
HOME_NET_UPDATE_CANARY='1'
```

Без canary-флага как ручной `apply`, так и daemon в режиме `apply` завершаются
ошибкой до скачивания installer. Остальные роутеры остаются в `check`.

После startup delay updater вычисляет стабильную задержку в пределах jitter по
первым hex-цифрам `/etc/machine-id`, а при его отсутствии — по MAC `eth0`.
`cksum`, Python и GNU coreutils не используются.

## Backup и фиксация версии

Перед применением создаётся:

```text
/root/home-net-update-backup-YYYYMMDD-HHMMSS/
```

В backup входят:

- release metadata;
- `VERSION`, `bundle.conf`, `install-all.sh` целевого release;
- текущий `/etc/home-net-update.conf`;
- текущий `/etc/home-net-update.state`;
- install metadata `from/to/tag/time`.

Если installer завершается ошибкой, новая версия не записывается. Компонентные
installer также сохраняют собственные backup.

## Post-apply health gate

После installer updater ждёт новый завершённый цикл Monitoring и требует:

```text
STATUS=OK
PODKOP=RUNNING
SING_BOX=RUNNING
FAKEIP=OK
SERVICE_CHECK=OK
```

`UNKNOWN`, `FAIL`, неполный state или timeout считаются неуспешным обновлением.
Новая bundle version не фиксируется, дальнейший rollout прекращается.

## Lock и восстановление

Одновременные проверки блокируются каталогом:

```text
/var/run/home-net-update.lock
```

Если PID из lock больше не существует, lock признаётся stale и автоматически
восстанавливается.

## Rollback

Автоматический rollback runtime-компонентов намеренно не выполняется: частичный
автоматический откат сетевых сервисов опаснее контролируемого восстановления.
При неуспешном health:

1. updater не меняет установленную bundle version;
2. пишет ошибку и путь backup в `logread`;
3. оператор анализирует Monitoring и компонентные backup;
4. при необходимости повторно запускает `install-all.sh` предыдущего стабильного
   release tag.

Пример ручного rollback к предыдущему release:

```sh
wget -qO /tmp/home-net-install-all.sh \
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/v1.5.1/install-all.sh

HOME_NET_BUNDLE_REF=v1.5.1 sh /tmp/home-net-install-all.sh
```

## Журнал

```sh
logread | grep home-net-update
```

Updater не меняет Podkop DNS, AmneziaWG или локальные пользовательские
конфигурации напрямую.
