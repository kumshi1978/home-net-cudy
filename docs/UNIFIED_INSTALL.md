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
HOME_NET_BUNDLE_VERSION='1.5.1'
FAILOVER_VERSION='1.4.1'
MONITORING_VERSION='1.4.2'
MONITORING_BOOTSTRAP_REF='4815fbacca19c26892a7880101abf902c83a9f81'
```

Bootstrap не должен устанавливать произвольный текущий `main` компонентов.

Каждый HOME NET bundle Release фиксирует точный набор протестированных версий.

## Что такое canary-router

**Canary-router** — это один заранее выбранный тестовый боевой Cudy, который получает новую опубликованную stable-версию раньше остальных роутеров HOME NET.

Он нужен для проверки релиза на реальном оборудовании до массового rollout. Если новая версия окажется проблемной, риск ограничивается одним заранее выбранным устройством, а остальные роутеры продолжают работать на уже проверенной версии.

Для HOME NET используется следующая схема:

- canary-router — `AUTO_UPDATE_MODE='apply'`;
- остальные Cudy — `AUTO_UPDATE_MODE='check'`;
- после успешной проверки новой версии на canary обновление разрешается остальным устройствам поэтапно;
- OpenWrt 24.x и OpenWrt 25.x считаются разными аппаратно-программными группами и проверяются отдельно.

Canary-router не является отдельным типом оборудования: это роль, которую мы назначаем одному из обычных Cudy для безопасного поэтапного обновления.

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

## Статус аппаратной проверки v1.5.1

HOME NET v1.5.1 проверен через единый `install-all.sh` на двух реальных Cudy:

- OpenWrt 24.10.4 — PASS;
- OpenWrt 25.12.5 — PASS.

На обеих системах подтверждены:

- Failover v1.4.1;
- Monitoring v1.4.2;
- активный `awg_main`;
- Podkop nft table и policy rule;
- `STATUS=OK`;
- `SERVICE_CHECK=OK`;
- `FAKEIP=OK`;
- updater/failover/health/monitoring daemons запущены.

Canary-router: квартирный основной Cudy / OpenWrt 24.10.4 с `AUTO_UPDATE_MODE='apply'`. Остальные роутеры по умолчанию остаются в `check`.

Начиная с HOME NET bundle v1.5.2 верхнеуровневый `home-net-update` обновляет
весь bundle по опубликованному HOME NET Release. Компонентный
`podkop-awg-update` пока остаётся установленным и продолжает работать по своей
отдельной политике до специального решения о консолидации.

## Единый updater

`home-net-update` реализован как отдельный procd-сервис. Он:

1. принимает только published non-draft/non-prerelease `vX.Y.Z` release;
2. сверяет `VERSION`, release tag и `bundle.conf`;
3. не выполняет downgrade или повторную установку;
4. скачивает `install-all.sh` только из точного release tag;
5. сохраняет backup конфигурации, bundle state и install metadata;
6. запускает installer с `HOME_NET_BUNDLE_REF="$release_tag"`;
7. ждёт новый цикл Monitoring и требует полный `STATUS=OK`;
8. фиксирует новую bundle version только после успешного health;
9. использует lock, startup delay и deterministic jitter;
10. разрешает `apply` только при явной роли canary.

Подробности и команды: `docs/HOME_NET_UPDATE.md`.

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
wget -qO /tmp/home-net-install-all.sh \
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/v1.5.2/install-all.sh

HOME_NET_BUNDLE_REF=v1.5.2 \
HOME_NET_AUTO_UPDATE_MODE=check \
sh /tmp/home-net-install-all.sh
```

После установки HOME NET updater остаётся в безопасном режиме:

```sh
HOME_NET_UPDATE_MODE='check'
HOME_NET_UPDATE_CANARY='0'
```

Для canary необходимо явно изменить оба значения. Production bootstrap и updater
должны быть привязаны к опубликованному HOME NET release tag, а не к `main`.
