# HOME NET Cudy — установка мониторинга

## Назначение

Служба контролирует состояние Podkop, sing-box, FakeIP и AmneziaWG на Cudy/OpenWrt.

## Быстрая установка из GitHub

Для v1.4.2:

```sh
wget -qO- https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/install.sh | sh
```

Bootstrap-установщик:

- проверяет, что система — OpenWrt;
- скачивает архив строго по релизному commit `4b407abcaa407f8b23c1c3b529466790fd2b242e`;
- проверяет, что `VERSION=1.4.2`;
- распаковывает архив во временный каталог `/tmp`;
- запускает встроенный `install/install.sh`;
- удаляет временные файлы после завершения.

Реальный GitHub token на роутере не требуется.

При необходимости ref можно переопределить переменной `HOME_NET_RELEASE_REF`, но для штатной установки v1.4.2 это не требуется.

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
