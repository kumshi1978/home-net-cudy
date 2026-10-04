# HOME NET Cudy — установка мониторинга

## Назначение

Служба контролирует состояние Podkop, sing-box, FakeIP и AmneziaWG на Cudy/OpenWrt.

## Быстрая установка из GitHub

Monitoring v1.4.3 пока является release candidate. После публикации tag:

```sh
wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install.sh | sh
```

Bootstrap-установщик v1.4.3:

- проверяет, что система — OpenWrt;
- скачивает архив строго по release commit
  `4ca7f606dfc4f1f9e8cca4b2fd7ab3158afcea00` либо явно заданному
  `HOME_NET_RELEASE_REF`;
- проверяет, что `MONITORING_VERSION=1.4.3`;
- распаковывает архив во временный каталог `/tmp`;
- запускает встроенный `install/install.sh`;
- удаляет временные файлы после завершения.

Реальный GitHub token на роутере не требуется.

До публикации release аппаратный тест выполняется только с явно заданным
commit SHA через `HOME_NET_RELEASE_REF`.

## Установка из уже скачанного репозитория

Из корня репозитория:

```sh
sh install/install.sh
```

Встроенный установщик:

- проверяет OpenWrt;
- делает backup текущих файлов;
- проверяет синтаксис shell-скриптов;
- устанавливает компоненты мониторинга;
- сохраняет существующий `/etc/podkop-service-check.conf`;
- перезапускает только `podkop-service-health`.

Он не должен перезапускать Podkop, sing-box, AmneziaWG или `podkop-awg-failover`.

## Устанавливаемые файлы

- `scripts/podkop-service-check`
- `scripts/podkop-service-health-daemon`
- `scripts/podkop-fakeip-check`
- `scripts/podkop-event-monitor`
- `scripts/podkop-event-runner`
- `scripts/podkop-country-lookup`
- `init.d/podkop-service-health`

Копируются в:

```text
/usr/bin/
/etc/init.d/
```

## Проверка после установки

```sh
cat /tmp/podkop-service-health/state
```

Ожидаемые параметры:

```text
STATUS=OK
PODKOP=RUNNING
SING_BOX=RUNNING
FAKEIP=OK
```

Дополнительно:

```sh
pgrep -af '/usr/bin/podkop-awg-failover'
nft list table inet PodkopTable >/dev/null 2>&1; echo "PodkopTable rc=$?"
ip rule show | grep -E 'lookup[[:space:]]+podkop([[:space:]]|$)'
```

## Backup

Перед изменением файлов встроенный installer создаёт/обновляет резервную копию:

```text
/root/backup-podkop-install/
```

## Совместимость и аппаратная проверка

Monitoring v1.4.2 аппаратно проверен на двух реальных Cudy:

- OpenWrt 24.10.4 — PASS;
- OpenWrt 25.12.5 — PASS.

Подтверждены:

- штатный `STATUS=OK`;
- `SERVICE_CHECK=OK`;
- `PODKOP=RUNNING`;
- `SING_BOX=RUNNING`;
- `FAKEIP=OK`;
- `podkop-service-check` возвращает rc=0;
- `podkop-fakeip-check` возвращает rc=0;
- FakeIP probes без `unifi.ui.com`;
- на OpenWrt 25.12.5 отдельно проверены `STATUS=UNKNOWN` и `STATUS=FAIL`;
- fail-fast предотвращает каскад внешних timeout;
- HTTP 451 обрабатывается как `REACHABLE/HTTP_DENIED`;
- installer не меняет Podkop DNS, AmneziaWG или failover сам по себе.

HOME NET bundle v1.5.1 с Monitoring v1.4.2 также прошёл unified-install тест на обеих ветках OpenWrt.

Monitoring v1.4.3 добавляет country-provider fallback
`ipinfo.io -> ipapi.co -> api.country.is`. До отдельной аппаратной проверки он
остаётся release candidate; подтверждённые результаты v1.4.2 выше сохраняются
как исторический baseline.
