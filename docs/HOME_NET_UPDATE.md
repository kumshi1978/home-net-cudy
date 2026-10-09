# HOME NET stable-release updater

`home-net-update` обновляет весь HOME NET bundle из опубликованного GitHub
Release `kumshi1978/home-net-cudy`. Он не заменяет и не удаляет существующий
компонентный `podkop-awg-update`.

Оба updater пока существуют параллельно и имеют независимые config/state/lock.
Bundle installer сохраняет текущий `AUTO_UPDATE_MODE` компонентного updater,
если оператор явно не передал `HOME_NET_AUTO_UPDATE_MODE`. Его код и release
channel верхнеуровневый updater не изменяет.

v1.5.2 — candidate/development: Monitoring 1.4.3, failover 1.4.1.
Bootstrap и архив Monitoring используют exact ref
`33a10d50846a7ff2672e399d933a532b752f4128`, без moving branch.

Первая установка сервиса: enable → running → start; работающий сервис получает
restart. Во время HOME_NET_UPDATE_IN_PROGRESS=1 текущий updater не перезапускается.
Self-update: временный файл рядом с destination → sh -n → chmod → mv.

## Файлы на роутере

```text
/usr/bin/home-net-update
/etc/init.d/home-net-update
/etc/home-net-update.conf
/etc/home-net-update.state
```

`/etc/home-net-update.state` хранит установленную и реально активированную версии
HOME NET bundle отдельно от версии failover:

```text
INSTALLED_VERSION='1.5.3'
ACTIVE_VERSION='1.5.2'
UPDATE_STATUS='PENDING_APPLY'
PENDING_ACTION='reboot'
PENDING_REASON='reboot activation required'
PENDING_VERSION='1.5.3'
PENDING_BOOT_ID='...'
LAST_UPDATE='2026-10-04 12:00:00'
LAST_HEALTH_STATUS='OK'
INSTALL_SOURCE='stable-release'
```

Состояние выводится командой:

```sh
/usr/bin/home-net-update status
```

`UPDATE_STATUS` проходит через следующие состояния:

- `OK` — installed и active совпадают, health успешен;
- `UPDATE_AVAILABLE` — найден более новый stable release;
- `INSTALLING` — installer выполняется;
- `VERIFYING` — ожидается post-update Monitoring cycle;
- `PENDING_APPLY` — файлы установлены, disruptive activation отложена;
- `FAILED` — installer или activation/health завершились неуспешно.

## Стратегия обновлений и восстановления

Каждый release объявляет в `bundle.conf` класс действия:

```text
UPDATE_ACTION_CLASS='SAFE|CONTROLLED|CRITICAL'
UPDATE_PENDING_ACTION='none|reboot|network_restart|...'
UPDATE_PENDING_REASON='...'
```

### SAFE

Автоматически устанавливаются скрипты HOME NET, Monitoring и updater, если
bundle не меняет runtime-версию failover. После нового Monitoring cycle и
успешного health gate повышается `ACTIVE_VERSION`. Установка файлов уже
фиксируется отдельно как `INSTALLED_VERSION`, даже если проверка не прошла.

### CONTROLLED

Перед применением updater проверяет IPv4 default route, active VPN, отсутствие
`/var/run/podkop-recovery.lock`, текущий health и удержание update lock. Затем
создаётся `/var/run/home-net-update.in-progress`, а `podkop-health` временно
останавливается, чтобы не запустить конкурирующий recovery. Monitoring продолжает
работать. После installer `podkop-health` запускается, updater ждёт bounded health
verification и только при `OK` повышает active version.

`UNKNOWN` повторно проверяется в пределах timeout и retry limit. `FAIL` также
получает ограниченное окно для штатного recovery `podkop-health`; бесконечных
restart loops updater не создаёт.

### CRITICAL

Автоматическая disruptive activation запрещена. Installer запускается только в
`HOME_NET_STAGE_ONLY=1`: runtime failover activation пропускается. После успешной
установки безопасной части и health gate записывается:

```text
INSTALLED_VERSION=new
ACTIVE_VERSION=old
UPDATE_STATUS=PENDING_APPLY
```

Updater никогда автоматически не выполняет:

- `/etc/init.d/network restart` или reload;
- `service network restart` или reload;
- `reboot`;
- изменение LAN/WAN и `/etc/config/network`.

Кроме классификации, скачанные installer проверяются на прямые команды network
restart/reload и reboot. Обнаружение такой команды останавливает update.

### Reboot pending

Для `PENDING_ACTION='reboot'` автоматический reboot не выполняется. State хранит
boot ID момента установки. После следующего штатного reboot daemon обнаруживает
новый boot ID и повышает `ACTIVE_VERSION` до `INSTALLED_VERSION` только если
текущий health полностью `OK`. Иначе pending сохраняется.

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

## Конфигурация и rollout rings

Новая локальная модель хранит способность к автоматическому обновлению и
постоянную роль роутера:

```text
HOME_NET_AUTO_UPDATE_CAPABLE='1'
HOME_NET_ROLLOUT_RING='canary|stable'
HOME_NET_ROLLOUT_POLICY_URL='https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/rollout-policy.conf'
```

Целевая раскладка:

- квартира backup Cudy — `canary`;
- квартира main Cudy — `stable`;
- дача main Cudy — `stable`;
- дача backup Cudy — `stable`.

Все четыре Cudy могут иметь `HOME_NET_AUTO_UPDATE_CAPABLE='1'`. Решение о
конкретном release принимает централизованная mutable policy:

```text
POLICY_SCHEMA='1'
RELEASE_TAG='vX.Y.Z'
ROLLOUT='manual|canary|fleet'
```

Смысл policy:

- `manual` — automatic apply запрещён всем;
- `canary` — automatic apply разрешён только ring=`canary`;
- `fleet` — automatic apply разрешён ring=`canary` и ring=`stable`.

Один immutable release/tag можно последовательно продвинуть
`manual -> canary -> fleet`, меняя только policy, без нового release.

### Fail-closed

Mutable policy никогда не выполняется как shell. Updater не делает `source`
этого файла и принимает только три известных поля с допустимыми значениями.
Недоступная policy, неизвестное поле, невалидное значение или несовпадение
`RELEASE_TAG` с latest stable release запрещают automatic apply.

Rollout policy не может обойти:

- update lock;
- preflight;
- backup;
- action class;
- post-update health verification;
- запрет автоматического disruptive activation для CRITICAL.

CRITICAL release при разрешённом rollout может автоматически установить только
безопасную staging-часть. Reboot/network activation остаются
`PENDING_APPLY`.

### Состояния rollout

Updater сохраняет runtime cache в:

```text
/tmp/home-net-update/rollout.state
```

Он содержит latest release, rollout, policy status и итоговый gate. Для UI
используются понятные состояния:

- `WAITING FOR CANARY` — release ещё в manual;
- `WAITING FOR FLEET` — release открыт canary, но этот router ring=stable;
- `AUTO APPLY ALLOWED` — policy разрешает auto-apply этому router;
- `POLICY BLOCKED` — policy недоступна/невалидна/не соответствует release;
- `AUTO UPDATE DISABLED` — локальная capability выключена.

### Обратная совместимость и миграция

`HOME_NET_UPDATE_MODE` и `HOME_NET_UPDATE_CANARY` сохраняются. Если оба новых
ключа отсутствуют, updater работает в legacy-режиме с прежней семантикой:
`mode=apply + canary=1` для автоматического apply. Это позволяет обновить код
updater без неожиданного изменения поведения существующих Cudy.

Миграция выполняется явным добавлением новых ключей в локальный config. Роль
роутера не выводится автоматически из hostname или старого canary-флага, потому
что постоянный canary теперь переносится на квартирный backup Cudy.

В новой модели ручной `home-net-update apply` считается явным действием
оператора и не зависит от release rollout policy. При этом lock, backup,
action-class ограничения, preflight и health gates остаются обязательными.

Существующий `/etc/home-net-update.conf` при повторной установке не
перезаписывается.

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

`UNKNOWN`, `FAIL`, неполный state или timeout не позволяют повысить
`ACTIVE_VERSION`. Если installer уже успешно записал файлы, новая версия
фиксируется как `INSTALLED_VERSION`, а state становится `FAILED`.

Прямой bootstrap через `install-all.sh` применяет тот же набор обязательных
полей и принимает только новый завершённый Monitoring cycle. При неуспехе он
возвращает ненулевой код, сохраняет новую `INSTALLED_VERSION`, но оставляет
предыдущую `ACTIVE_VERSION`. Если прежняя active-version достоверно неизвестна,
в state явно записывается `ACTIVE_VERSION='unknown'`.

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

1. при ошибке installer updater не меняет installed/active version;
2. при ошибке активации installed version может быть новой, но active version
   остаётся прежней;
3. updater пишет ошибку и путь backup в `logread`;
4. оператор анализирует Monitoring и компонентные backup;
5. при необходимости повторно запускает `install-all.sh` предыдущего стабильного
   release tag.

## Coordination limitation

Текущая версия координируется с `podkop-health`, временно останавливая его на
время CONTROLLED installer, и использует собственный marker. Репозитории
`podkop-awg-failover` и `podkop-late-start` пока не читают этот marker. Для общей
межрепозиторной блокировки recovery потребуется отдельный PR в failover repo;
это не включено в текущий PR.

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
