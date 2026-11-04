# Hardware canary — apartment-backup Cudy

## Цель

Первый аппаратный тест HOME NET v1.8.0 выполняется вручную на резервном квартирном Cudy.

Известная платформа:

- Cudy TR3000 256MB v1
- OpenWrt 25.12.5

Work/CI не подключаются к устройству. Все команды на реальном Cudy выполняются отдельно в основном ChatGPT-чате.

## Важное отличие от старой lab-схемы

Для v1.8.0 **не требуется останавливать и отключать Failover** на время normal secure transaction.

HOME NET и Failover 1.4.2 координируются через общий kernel `flock`:

```
/var/run/home-net-vpn-maintenance.lock
```

Если lock занят другой стороной, conflicting writer не входит в critical section.

## Phase 0 — baseline

До изменений зафиксировать без вывода secrets:

- board/model;
- OpenWrt version;
- HOME NET version;
- Failover version;
- current active VPN;
- Podkop status;
- sing-box status;
- `awg_main` / `awg_backup` health;
- package manager;
- наличие `age` и `age-keygen`;
- free flash.

## Phase 1 — backup

До установки candidate подготовить локальный rollback для:

- Failover 1.4.1;
- текущей HOME NET installation;
- LuCI HOME NET files;
- relevant HOME NET configs/state.

Rollback procedure должен быть известен до upgrade.

## Phase 2 — Failover 1.4.2 candidate

Установить только immutable candidate SHA.

После установки проверить:

- active Podkop interface не изменился;
- интернет работает;
- штатный failover работает;
- DNS/NTP settings не изменились;
- stopped services не запустились неожиданно.

## Phase 3 — HOME NET v1.8 candidate

Установить только immutable HOME NET SHA.

На этом этапе:

- не создавать identity;
- не устанавливать/не включать secure migration автоматически;
- не менять VPN profile.

Главный критерий — Legacy mode работает как до upgrade.

## Phase 4 — observation

Проверить:

- HOME NET status;
- LuCI;
- Podkop;
- failover;
- current active VPN;
- internet;
- non-secret logs.

## Phase 5 — crypto capability

Отдельно проверить доступность `age` / `age-keygen`.

Если crypto tools отсутствуют, это не считается failure Legacy upgrade.

## Phase 6 — identity initialization

Только отдельным явным действием оператора.

Initialization не должна менять active VPN.

## Phase 7 — encrypted candidate

После отдельного разрешения:

1. Upload encrypted `.conf.age`.
2. Prepare.
3. Verify.
4. Explicit Promote.
5. Rollback test.

Перед Promote повторно проверяется actual active slot. Если он изменился после Prepare, Promote должен fail-safe остановиться.

## Reboot/session safety

Не выполнять destructive fault injection без необходимости.

Проверять безопасно:

- page reload/session loss не изменяет backend transaction;
- после reboot незавершённый Promote не продолжается автоматически;
- stale lock file без удерживаемого flock не блокирует систему навсегда.

## Acceptance

Canary считается успешным только если:

- Failover 1.4.2 upgrade не меняет baseline network state;
- HOME NET v1.8 Legacy upgrade не меняет baseline VPN;
- LuCI Secure VPN работает без раскрытия secrets;
- Prepare/Verify не меняют active traffic;
- Promote происходит только явно;
- Rollback возвращает исходное состояние;
- штатный failover после transaction продолжает работу.

До успешного canary PR #29 остаётся draft. Merge/tag/Release запрещены.
