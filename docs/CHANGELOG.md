# История изменений HOME NET

## v1.5.0 — HOME NET Monitoring logging

Добавлено:
- пассивный problem logger для событий Monitoring/Podkop/failover/updater/dnsmasq/sing-box;
- opt-in DNS domain capture через dnsmasq query logging;
- классификация наблюдений FAKEIP и DIRECT_OR_UNKNOWN;
- отчёт по наиболее частым наблюдаемым доменам;
- manual incident snapshot с health + recent problems + recent domains;
- подробные логи хранятся в tmpfs, без постоянной записи на flash;
- domain capture никогда не включается автоматически при bundle update;
- никакие domain lists и routing policy автоматически не изменяются.


## v1.4.4 — HOME NET Monitoring

Исправлено:
- добавлен bounded startup readiness wait перед первым health cycle;
- Monitoring ждёт готовности sing-box, runtime Podkop routing и FakeIP DNS перед первой оценкой;
- ложный ранний HOME NET FAIL после reboot больше не должен фиксироваться, пока сервисы находятся в штатной boot-фазе;
- таймаут по умолчанию 120 секунд, poll interval 5 секунд;
- после истечения startup grace выполняется обычная оценка и реальная неисправность остаётся видимой;
- параметры можно переопределить через MONITORING_STARTUP_GRACE и MONITORING_STARTUP_POLL_INTERVAL.


## v1.4.1 — HOME NET Monitoring

Дата релиза: 2026-09-04

Добавлено и исправлено:

- разделение health state и event pipeline;
- `podkop-event-monitor` для фиксации переходов состояния;
- `podkop-event-runner` как слой обработки событий;
- health-daemon вызывает event pipeline после успешного atomic обновления state;
- atomic обновление state-файлов;
- безопасный разбор state-файлов в event-monitor;
- улучшенная проверка FakeIP DNS с настраиваемым списком доменов;
- исправленные exit codes для service-check;
- отдельные проверки Podkop и sing-box;
- Podkop health определяется по runtime routing (`inet PodkopTable` + `lookup podkop`), а не по `procd running=true`;
- корректная обработка отсутствующего `awg_backup`;
- восстановлены `AWG_MAIN_COUNTRY` и `AWG_BACKUP_COUNTRY` в state;
- восстановлено разделение `ACTIVE_COUNTRY` и `WAN_COUNTRY`;
- сохранена очистка ежедневных логов по `KEEP_DAYS`;
- installer сохраняет существующий `/etc/podkop-service-check.conf`;
- installer копирует и chmod только файлы мониторинга;
- добавлен публичный bootstrap-установщик из GitHub.

Компоненты:

- `podkop-service-check`;
- `podkop-service-health-daemon`;
- `podkop-fakeip-check`;
- `podkop-event-monitor`;
- `podkop-event-runner`.

Аппаратная проверка v1.4.1:

- Cudy;
- OpenWrt 24.10.4;
- `STATUS=OK`;
- `PODKOP=RUNNING`;
- `SING_BOX=RUNNING`;
- `FAKEIP=OK`;
- event pipeline проверен на `OK -> FAIL -> OK` синтетическим тестом;
- отсутствие ложных событий при неизменном state подтверждено;
- PID `podkop-awg-failover` не изменился во время установки и тестов;
- активный VPN остался `awg_main`.

OpenWrt 25.x: код рассчитан на совместимость, но аппаратная проверка v1.4.1 ещё не выполнена. После проверки будет обновлена документация; если потребуется изменение кода, будет выпущена следующая patch-версия.

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
