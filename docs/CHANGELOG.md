# История изменений HOME NET

## v1.4.1-dev — HOME NET Monitoring

Добавлено и исправлено:

- разделение health state и event pipeline;
- podkop-event-monitor для фиксации переходов состояния;
- podkop-event-runner как слой обработки событий;
- atomic обновление state-файлов;
- безопасный разбор state-файлов в event-monitor;
- улучшенная проверка FakeIP DNS с настраиваемым списком доменов;
- исправленные exit codes для service-check;
- отдельные проверки Podkop и sing-box;
- корректная обработка отсутствующего awg_backup;
- восстановлены AWG_MAIN_COUNTRY и AWG_BACKUP_COUNTRY в state;
- восстановлено разделение ACTIVE_COUNTRY и WAN_COUNTRY;
- сохранена очистка ежедневных логов по KEEP_DAYS;
- расширенный install pipeline;
- installer сохраняет существующий /etc/podkop-service-check.conf при обновлении;
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

Перед финальным релизом требуется аппаратная проверка на Cudy/OpenWrt.

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
