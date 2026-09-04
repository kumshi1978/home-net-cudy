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

Причина: UniFi UDM/UDM SE использует служебные проверки WAN. На Cudy/OpenWrt 25.12.5 с Podkop 0.7.22 и sing-box 1.13.18 `ping.ui.com` был выдан как FakeIP `198.18.0.8`; UDM SE регулярно отправлял ICMP на этот адрес, после чего sing-box писал `missing fakeip record` примерно каждые 10–11 секунд.

## Штатный Podkop exclusion

Для Podkop используется отдельная section с:

```text
connection_type='exclusion'
user_domain_list_type='text'
user_domains_text='...'
```

После изменения конфигурации необходимо перезапустить Podkop и проверить фактический DNS-результат и логи.

## Важное ограничение Podkop 0.7.22

В Podkop существует известная проблема: домены из exclusion могут всё равно получать FakeIP. Поэтому наличие домена в exclusion не считается достаточным доказательством корректной работы.

После применения обязательно проверить:

```sh
nslookup ui.com 127.0.0.1
nslookup ping.ui.com 127.0.0.1
logread | grep 'missing fakeip record' | tail -20
```

Ожидаемое конечное состояние: `ui.com` и `ping.ui.com` не должны возвращаться как адреса из FakeIP-диапазона `198.18.0.0/15`, а повторяющиеся ошибки `missing fakeip record` должны прекратиться.

## Совместимость

Изменения списка должны отдельно проверяться на OpenWrt 24.x и 25.x с фактически установленными версиями Podkop/sing-box.
