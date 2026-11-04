# HOME NET VPN NAS controller — Deferred / Future

## Статус

NAS controller **не входит в обязательную архитектуру HOME NET v1.8.0**.

v1.8.0 использует local-first модель:

```
Cudy local identity -> local decrypt -> prepare -> verify -> promote -> rollback
```

Обычный upgrade HOME NET, Legacy mode, secure initialization и hardware canary не зависят от NAS.

## Что отложено

На будущий этап отложены:

- central secrets/controller service;
- центральное хранение encrypted deployments;
- fleet orchestration;
- recipient registry;
- автоматическая доставка encrypted candidates;
- централизованные backups.

Если такой controller будет реализован позже, он не должен требовать передачи private router identities на NAS.

## Допустимое использование NAS сейчас

NAS может использоваться:

- как лабораторный hypervisor для будущего OpenWrt VM Lab;
- как обычное private backup location по отдельному решению пользователя;
- для разработки и тестирования инструментов.

Это не делает NAS prerequisite для HOME NET v1.8.0.

## Security rule

Private identity Cudy остаётся локально на роутере.

Нельзя считать NAS обязательным escrow для router key.

Optional recovery recipient может быть добавлен в будущем, но его отсутствие не блокирует HOME NET upgrade или secure initialization.
