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

**v1.5.0 — HOME NET unified bundle.**

Состав bundle:

- Failover / updater: `openwrt-podkop-awg-failover v1.4.1`;
- HOME NET Monitoring: `v1.4.1`.

Аппаратно протестировано на Cudy / OpenWrt 24.10.4:

- единая установка failover + Monitoring;
- повторная установка без потери пользовательской конфигурации;
- сохранение `AUTO_UPDATE_MODE=apply` на canary-router;
- `awg_main` остаётся активным;
- failover, health и updater watchdogs работают;
- Monitoring сообщает `STATUS=OK`;
- Podkop, sing-box и FakeIP работают;
- stable updater успешно обновил failover `1.4.0 -> 1.4.1`.

OpenWrt 25.x будет проверен следующим этапом. До завершения аппаратной проверки 25.x rollout следует выполнять сначала в режиме `check`.

## Единая установка HOME NET

Для обычного роутера безопасный режим автообновления по умолчанию — `check`:

```sh
wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install-all.sh | sh
```

Для canary-router можно явно включить `apply`:

```sh
wget -qO /tmp/home-net-install-all.sh \
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install-all.sh
HOME_NET_AUTO_UPDATE_MODE=apply sh /tmp/home-net-install-all.sh
```

Manifest `bundle.conf` фиксирует совместимую комбинацию компонентных версий. Failover и Monitoring остаются отдельными компонентами и могут версионироваться независимо.

## Только Monitoring

Старый bootstrap Monitoring сохранён для отдельной установки:

```sh
wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install.sh | sh
```

Он устанавливает проверенный Monitoring v1.4.1 из зафиксированного commit.

Подробности:

- `docs/INSTALL.md` — Monitoring;
- `docs/UNIFIED_INSTALL.md` — архитектура общего bundle;
- failover auto-update: `openwrt-podkop-awg-failover/docs/AUTO_UPDATE.md`.
