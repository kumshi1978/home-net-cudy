# Router VPN deployment transaction

## Назначение

HOME NET v1.8.0 выполняет secure VPN deployment локально на Cudy.

Router helper работает только с заранее существующими слотами `awg_main` и `awg_backup` и не требует NAS.

Identity хранится локально:

```
/etc/home-net/keys/age-identity.txt
```

mode 0600, каталог `/etc/home-net/keys` — mode 0700.

## Adapter contract

Все verbs синхронные и возвращают nonzero при ошибке. Только `active` пишет slot в stdout.

| Verb | Поведение |
| --- | --- |
| active | вывести `awg_main` или `awg_backup` |
| validate TARGET PLAINTEXT | проверить AWG config без изменения сети |
| snapshot PREVIOUS TARGET BACKUP_DIR | сохранить rollback material |
| stage PREVIOUS TARGET PLAINTEXT | применить candidate только в inactive slot |
| verify PREVIOUS TARGET COUNTRY | проверить candidate, handshake, egress, country и Podkop/sing-box health |
| promote PREVIOUS TARGET | переключить policy на candidate |
| check-promoted TARGET COUNTRY | проверить promoted state |
| restore PREVIOUS TARGET BACKUP_DIR | восстановить предыдущую рабочую конфигурацию |
| check-restored PREVIOUS TARGET BACKUP_DIR | подтвердить rollback |

## Maintenance coordination

HOME NET и Failover 1.4.2 используют один kernel lock:

```
/var/run/home-net-vpn-maintenance.lock
```

Каждая critical operation берёт `flock`, повторно читает actual active slot и только после этого выполняет write.

Lock не удерживается между отдельными ручными этапами Prepare и Promote.

Если active slot изменился между Prepare и Promote, Promote завершается fail-safe и transaction переходит в recovery-required/error state.

Наличие lock-файла без удерживаемого `flock` не считается активной maintenance operation.

## Operator flow

### Legacy upgrade

Обычный HOME NET upgrade:

- не требует `age`;
- не создаёт identity;
- не меняет active VPN;
- не мигрирует secrets автоматически.

### Secure flow

1. Initialize local identity.
2. Upload encrypted `.conf.age`.
3. Prepare inactive slot.
4. Verify candidate.
5. Explicit Promote.
6. Rollback при необходимости.

Backend upload ограничен 64 KiB и не использует user-supplied filename.

## Reboot/session safety

Browser/LuCI session не является владельцем transaction.

После reboot:

- автоматический Promote запрещён;
- незавершённая transaction определяется по persisted state/boot-id;
- оператор получает recovery-required и выполняет явный Rollback/recovery.

## Rotation

Identity rotation выполняется вручную через candidate key:

1. stage;
2. verify public recipient;
3. explicit promote;
4. rollback при необходимости.

Предыдущий key сохраняется как local recovery material и не удаляется автоматически.

## Deferred

NAS controller, central key distribution и OpenWrt 24/25 VM Lab не входят в обязательный scope v1.8.0.
