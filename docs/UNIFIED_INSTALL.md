# HOME NET — единая установка и обновления

## Решение

Репозитории компонентов не объединяются физически.

`home-net-cudy` становится верхнеуровневым HOME NET bootstrap/orchestrator, а специализированные компоненты продолжают жить и версионироваться отдельно.

Текущие компоненты:

1. `kumshi1978/openwrt-podkop-awg-failover`
   - AmneziaWG main/backup failover;
   - Podkop late-start;
   - Podkop health recovery;
   - stable-release updater;
   - fail-closed/hold.

2. `kumshi1978/home-net-cudy`
   - HOME NET Monitoring;
   - health state;
   - event monitoring;
   - общая точка установки HOME NET.

## Почему не один монорепозиторий

Отдельные компоненты позволяют:

- выпускать hotfix failover без изменения monitoring;
- тестировать OpenWrt 24.x и 25.x отдельно;
- откатывать один компонент независимо;
- сохранять понятные VERSION/Release для каждого компонента;
- не заставлять monitoring-пакет перезапускать Podkop/AWG;
- не смешивать runtime-critical failover с read-only monitoring.

## Целевая схема установки

Пользователь запускает одну команду HOME NET bootstrap.

Bootstrap:

1. проверяет OpenWrt и базовые зависимости;
2. проверяет наличие Podkop и двух AmneziaWG интерфейсов;
3. читает release manifest HOME NET;
4. устанавливает точную stable-версию failover по release tag;
5. устанавливает точную проверенную версию Monitoring по release ref/tag;
6. сохраняет локальные конфигурации;
7. включает updater policy;
8. выполняет post-install health checks;
9. печатает единый итоговый статус.

## Release manifest

HOME NET bundle должен хранить явные версии компонентов, например:

```text
HOME_NET_BUNDLE_VERSION='1.0.0'
FAILOVER_VERSION='1.4.1'
MONITORING_VERSION='1.4.1'
MONITORING_REF='d29183b745e1fee7f1ab999f37e7aacf564c18fd'
```

Bootstrap не должен устанавливать произвольный текущий `main` компонентов.

Каждый HOME NET bundle Release фиксирует точный набор протестированных версий.

## Политика обновлений

### По умолчанию

Все роутеры:

```text
AUTO_UPDATE_MODE='check'
```

### Canary

Один выбранный Cudy:

```text
AUTO_UPDATE_MODE='apply'
```

Новая stable-версия сначала автоматически попадает только на canary-router.

После аппаратной проверки:

- OpenWrt 24.x;
- OpenWrt 25.x;
- Podkop;
- sing-box;
- FakeIP;
- awg_main / awg_backup;
- Monitoring STATUS=OK;

версия разрешается для следующей волны роутеров.

## Единый updater

На первом этапе компонентный updater `openwrt-podkop-awg-failover` остаётся источником автоматического обновления failover.

HOME NET bootstrap управляет его политикой (`check`/`apply`) и устанавливает Monitoring.

На следующем этапе можно добавить верхнеуровневый `home-net-update`, который будет обновлять не отдельный файл, а весь HOME NET bundle по опубликованному stable HOME NET Release/manifest.

Такой updater должен:

1. принимать только published non-draft/non-prerelease release;
2. проверять bundle manifest;
3. не выполнять downgrade;
4. создавать backup перед каждым компонентом;
5. применять компоненты в фиксированном порядке;
6. проверять health после каждого шага;
7. прекращать rollout при ошибке;
8. поддерживать canary policy и jitter.

## Порядок компонентов

Рекомендуемый порядок:

1. failover/updater;
2. проверка `awg_main`, watchdog и Podkop;
3. Monitoring;
4. итоговая проверка `/tmp/podkop-service-health/state`.

Monitoring не должен перезапускать Podkop, sing-box, AWG или failover.

## Секреты

Единый installer не должен содержать или скачивать из публичного GitHub:

- AmneziaWG private keys;
- preshared keys;
- пароли;
- токены;
- полные `/etc/config/network` с секретами.

Installer работает поверх уже существующей локальной конфигурации роутера.

## Целевой UX

После выпуска HOME NET bundle пользователь должен иметь одну команду установки, например:

```sh
wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install-all.sh | sh
```

Для canary:

```sh
HOME_NET_UPDATE_MODE=apply wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install-all.sh | sh
```

Перед production rollout bootstrap должен быть привязан к опубликованному HOME NET release/commit, а не динамически устанавливать текущее содержимое component `main`.
