# HOME NET Cudy — установка мониторинга

## Назначение

Служба контролирует состояние Podkop, sing-box, FakeIP и AmneziaWG на Cudy/OpenWrt.

## Установка

Основной способ установки:

```sh
sh install/install.sh
```

Установщик:

- проверяет OpenWrt;
- делает backup текущих файлов;
- проверяет синтаксис shell-скриптов;
- устанавливает компоненты мониторинга.

## Устанавливаемые файлы

- scripts/podkop-service-check
- scripts/podkop-service-health-daemon
- scripts/podkop-fakeip-check
- scripts/podkop-event-monitor
- scripts/podkop-event-runner
- init.d/podkop-service-health

Копируются в:

```
/usr/bin/
/etc/init.d/
```

## Проверка после установки

```sh
cat /tmp/podkop-service-health/state
```

Ожидаемые параметры:

```
STATUS=OK
PODKOP=RUNNING
SING_BOX=RUNNING
FAKEIP=OK
```

## Backup

Перед изменением файлов создаётся резервная копия:

```
/root/backup-podkop-install/
```

## Совместимость

Проверка выполняется для OpenWrt 24.x и 25.x.
