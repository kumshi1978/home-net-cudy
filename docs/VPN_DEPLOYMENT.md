# HOME NET v1.8.0 — local-first secure VPN deployment

## Цель

HOME NET v1.8.0 добавляет безопасную замену AmneziaWG-профиля без обязательного участия NAS и без принудительной миграции при обычном обновлении HOME NET.

На каждом Cudy используются два заранее существующих слота:

- `awg_main`
- `awg_backup`

Новый профиль всегда готовится в неактивном слоте. Переключение выполняется только отдельной явной командой `Promote`.

## Ключевые принципы

- Обычный upgrade HOME NET не требует `age`.
- Отсутствие `age` или identity не мешает Legacy mode.
- Identity создаётся локально на Cudy только по явной команде оператора.
- Private identity не покидает Cudy.
- Encrypted candidate расшифровывается локально.
- Prepare и Verify не меняют active VPN.
- Promote разрешён только после Verify.
- Rollback восстанавливает предыдущий слот и сохранённое состояние.
- HOME NET и Failover 1.4.2 координируют изменения через общий kernel `flock`.

## Состояния

Secure subsystem допускает состояния:

- `UNAVAILABLE` — нет необходимых crypto tools;
- `NOT INITIALIZED` — crypto tools доступны, identity ещё не создана;
- `READY` — identity валидна;
- transaction phases: `preparing`, `prepared`, `verified`, `promoting`, `promoted`, `restoring`, `rolled-back`, `recovery-required`.

После reboot незавершённый Promote автоматически не продолжается.

## Identity

Рекомендуемые пути:

```
/etc/home-net/keys/
/etc/home-net/keys/age-identity.txt
/etc/home-net/keys/age-recipient.txt
```

Требования:

- каталог: mode 0700;
- private identity: mode 0600;
- public recipient можно показывать в LuCI;
- private identity нельзя выводить в LuCI, logs, process argv или Git.

Канонические Router ID:

- `apartment-main`
- `apartment-backup`
- `dacha-main`
- `dacha-backup`

## Upload и transaction

LuCI передаёт только encrypted `.conf.age`.

Backend:

- ограничивает upload 64 KiB;
- ограничивает время чтения;
- не доверяет имени пользовательского файла;
- использует закрытый temporary directory;
- выбирает inactive slot только под maintenance lock;
- минимизирует время жизни plaintext;
- не возвращает plaintext frontend.

Цикл:

```
upload -> prepare -> verify -> promote
                     \-> rollback
```

Перед каждой критической операцией фактический active slot перечитывается заново.

Если active slot изменился между Prepare и Promote, Promote завершается fail-safe и требует вмешательства оператора.

## Координация с Failover

HOME NET v1.8 secure transaction согласован с Failover 1.4.2.

Общий lock:

```
/var/run/home-net-vpn-maintenance.lock
```

Важно: существование файла не означает активную блокировку. Решение принимает kernel `flock`.

Во время критической секции failover/recovery writers не меняют active VPN. После освобождения lock штатный failover продолжает работу.

## Legacy mode

До явной secure initialization и migration текущие:

- `awg_main`;
- `awg_backup`;
- Podkop;
- sing-box;
- failover;
- DNS/FakeIP;
- routing policy

должны продолжать работать без изменений.

## Recovery и rotation

Rotation выполняется вручную:

1. сохранить прежнюю identity;
2. создать candidate identity;
3. получить candidate public recipient;
4. verify;
5. explicit promote;
6. rollback при необходимости.

Старая identity не удаляется автоматически. Старые `.conf.age`, зашифрованные только на прежний recipient, могут требовать старый ключ.

Recovery не зависит от NAS. Optional recovery recipient допускается, но не является обязательным условием upgrade, initialization или Legacy mode.

## Deferred

В v1.8.0 отложены:

- NAS controller;
- central key distribution;
- OpenWrt 24.x VM Lab;
- OpenWrt 25.x VM Lab.

NAS может использоваться как лабораторный hypervisor, но не является обязательным secrets/controller компонентом v1.8.0.

## Hardware canary

Первый реальный тест выполняется вручную на `apartment-backup`.

До hardware-canary PR остаётся draft. Merge, tag и Release выполняются только после отдельного решения по результатам аппаратной проверки.
