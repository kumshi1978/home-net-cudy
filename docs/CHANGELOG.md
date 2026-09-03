# История изменений HOME NET

## v1.4.1-dev — HOME NET Monitoring

Добавлено и исправлено:

- разделение health state и event pipeline;
- podkop-event-monitor для фиксации переходов состояния;
- podkop-event-runner как слой обработки событий;
- atomic обновление state-файлов;
- улучшенная проверка FakeIP DNS;
- исправленные exit codes для service-check;
- расширенный install pipeline;
- установка и проверка всех компонентов мониторинга.

Компоненты:

- podkop-service-check;
- podkop-service-health-daemon;
- podkop-fakeip-check;
- podkop-event-monitor;
- podkop-event-runner.

Совместимость:

- OpenWrt 24.10.x;
- OpenWrt 25.12.x;
- BusyBox ash.

## v1.3.9 — базовый мониторинг

Добавлено:

- мониторинг состояния Cudy/OpenWrt;
- проверка AmneziaWG туннелей;
- проверка Podkop;
- проверка sing-box;
- проверка FakeIP DNS;
- контроль внешнего IP и страны выхода VPN;
- state-файл состояния системы;
- ежедневные диагностические логи.

Проверено на:

- Cudy
- OpenWrt 25.x
- Podkop 0.7.22
