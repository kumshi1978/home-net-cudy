# HOME NET — Cudy / OpenWrt / Podkop / AmneziaWG

Проект управления домашней сетью на базе роутеров Cudy с OpenWrt.

## Назначение

Цель проекта — единая, проверяемая и версионируемая конфигурация для всех Cudy:

- Podkop
- sing-box
- AmneziaWG
- VPN маршрутизация
- контроль доступности сервисов
- диагностика и автоматизация

## Принципы проекта

- GitHub является источником истины.
- Изменения сначала проверяются на тестовом роутере.
- Локальные отличия устройств фиксируются отдельно.
- Документация и комментарии ведутся на русском языке.
- Реальные VPN private keys, PSK, пароли и токены в репозиторий не сохраняются.

## Текущая версия

**Stable: v1.5.2. Development candidate: v1.5.3.**

v1.5.3 обновляет Monitoring до v1.4.4 и добавляет bounded startup readiness wait перед первым health cycle, чтобы не фиксировать ложный ранний FAIL во время штатной загрузки Podkop/sing-box.

Состав bundle:

- Failover / updater: `openwrt-podkop-awg-failover v1.4.1`;
- HOME NET Monitoring: `v1.4.4` в candidate v1.5.3; stable v1.5.2 содержит Monitoring v1.4.3.

Bundle устанавливает `/usr/bin/home-net-update`, который проверяет только
опубликованные stable GitHub Releases `home-net-cudy` и обновляет весь совместимый
набор из `bundle.conf`. Компонентный `podkop-awg-update` пока сохраняется отдельно.

Аппаратная проверка stable v1.5.2 завершена на обеих поддерживаемых ветках OpenWrt:

- квартирный основной Cudy / OpenWrt 24.10.4 — PASS;
- квартирный резервный Cudy / OpenWrt 25.12.5 — PASS.

На обеих системах подтверждены HOME NET v1.5.2, Failover v1.4.1, Monitoring v1.4.3, работа Podkop/sing-box/FakeIP и итоговый `STATUS=OK`. На OpenWrt 25.12.5 дополнительно пройден reboot-test; выявленный ранний Monitoring boot-race исправляется candidate v1.5.3 / Monitoring v1.4.4.

Текущая rollout-политика:

- квартирный основной Cudy / OpenWrt 24.10.4 — canary-router, `AUTO_UPDATE_MODE='apply'`;
- квартирный резервный Cudy / OpenWrt 25.12.5 — `AUTO_UPDATE_MODE='check'`;
- дачные Cudy обновляются отдельной волной, когда будет доступ к площадке.

## Единая установка HOME NET

Для обычного роутера безопасный режим HOME NET updater по умолчанию — `check`.
После публикации stable release установка будет выполняться по фиксированному tag:

```sh
wget -qO /tmp/home-net-install-all.sh \
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/v1.5.2/install-all.sh

HOME_NET_BUNDLE_REF=v1.5.2 \
HOME_NET_AUTO_UPDATE_MODE=check \
sh /tmp/home-net-install-all.sh
```

После установки проверить HOME NET release без применения:

```sh
/usr/bin/home-net-update check
/usr/bin/home-net-update status
```

Автоматический `apply` разрешается только на заранее выбранном canary-router и
требует одновременно `HOME_NET_UPDATE_MODE='apply'` и
`HOME_NET_UPDATE_CANARY='1'` в `/etc/home-net-update.conf`.

Release действия классифицируются как `SAFE`, `CONTROLLED` или `CRITICAL`.
CRITICAL activation всегда остаётся `PENDING_APPLY`: updater не выполняет
автоматический reboot или restart/reload сети.

Manifest `bundle.conf` фиксирует совместимую комбинацию компонентных версий. Failover и Monitoring остаются отдельными компонентами и могут версионироваться независимо.

## Только Monitoring

Старый bootstrap Monitoring сохранён для отдельной установки:

```sh
wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install.sh | sh
```

Он устанавливает проверенный Monitoring v1.4.3 из зафиксированного commit.

Подробности:

- `docs/INSTALL.md` — Monitoring;
- `docs/UNIFIED_INSTALL.md` — архитектура общего bundle;
- `docs/HOME_NET_UPDATE.md` — check/apply/canary, backup, health и rollback;
- failover auto-update: `openwrt-podkop-awg-failover/docs/AUTO_UPDATE.md`.
