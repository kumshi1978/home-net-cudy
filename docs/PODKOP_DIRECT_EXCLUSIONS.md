# HOME NET — Podkop direct exclusions

## Назначение

Файл `configs/podkop-direct-exclusions.txt` — общий источник истины HOME NET для доменов, которые должны идти напрямую, минуя VPN/FakeIP, если это поддерживается текущей версией Podkop.

Локальные исключения конкретного роутера должны документироваться отдельно и не добавляться сюда без необходимости.

## UniFi health-check

В общий список включены:

```text
ui.com
ping.ui.com
```

Причина: UniFi UDM/UDM SE использует служебные проверки WAN. На Cudy/OpenWrt 25.12.5 с Podkop 0.7.22 и sing-box 1.13.18 `ping.ui.com` попадал в FakeIP через родительский домен `ui.com`. После удаления `ui.com` и `ping.ui.com` из VPN-списка оба домена стали резолвиться в реальные публичные адреса.

Это устраняет конфликт UniFi health-check с FakeIP, но не считается исправлением отдельной upstream-проблемы `missing fakeip record` в Podkop/sing-box 1.13.18: на тестовом OpenWrt 25.12.5 эта ошибка продолжала воспроизводиться после reboot, пересоздания `cache.db`, остановки HOME NET monitoring/failover/health и переключения между `awg_main` и `awg_backup`.

## Штатный Podkop exclusion

Для Podkop используется отдельная section с:

```text
connection_type='exclusion'
user_domain_list_type='text'
user_domains_text='...'
```

После изменения конфигурации необходимо перезапустить Podkop и проверить фактический DNS-результат и логи.

## Monitoring и FakeIP probes

Домены, которые по политике HOME NET должны идти напрямую, нельзя одновременно использовать как обязательные FakeIP probes в Monitoring.

Поэтому `unifi.ui.com` исключён из `FAKEIP_DOMAINS`. Базовый набор проверки теперь:

```text
github.com
claude.ai
gemini.google.com
```

На OpenWrt 25.12.5 это проверено на реальном роутере: после удаления `unifi.ui.com` из `FAKEIP_DOMAINS` команда `/usr/bin/podkop-fakeip-check` вернула `RC=0`, а оставшиеся три домена получили FakeIP.

## Важное ограничение Podkop 0.7.22

В Podkop существует известная проблема: домены из exclusion могут всё равно получать FakeIP. Поэтому наличие домена в exclusion не считается достаточным доказательством корректной работы.

После применения обязательно проверить:

```sh
nslookup ui.com 127.0.0.1
nslookup ping.ui.com 127.0.0.1
/usr/bin/podkop-fakeip-check
logread | grep 'missing fakeip record' | tail -20
```

Ожидаемое состояние для direct-exclusion: `ui.com` и `ping.ui.com` не должны возвращаться как адреса из FakeIP-диапазона `198.18.0.0/15`. При этом наличие или отсутствие отдельной ошибки `missing fakeip record` оценивается отдельно, поскольку она воспроизводится и без UniFi health-check.

## Совместимость

Изменения списка и Monitoring должны отдельно проверяться на OpenWrt 24.x и 25.x с фактически установленными версиями Podkop/sing-box.
