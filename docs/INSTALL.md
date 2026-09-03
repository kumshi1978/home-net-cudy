# HOME NET Cudy — установка мониторинга

## Назначение

Служба контролирует состояние Podkop, sing-box и AmneziaWG на Cudy/OpenWrt.

## Установка

Файлы:

- scripts/podkop-service-check
- scripts/podkop-service-health-daemon
- scripts/podkop-fakeip-check
- init.d/podkop-service-health

Копируются в:

```
/usr/bin/
/etc/init.d/
```

## Запуск

```sh
chmod +x /usr/bin/podkop-*
/etc/init.d/podkop-service-health enable
/etc/init.d/podkop-service-health start
```

## Проверка

```sh
cat /tmp/podkop-service-health/state
```

## Совместимость

Проверяется на OpenWrt 24.x и 25.x.
