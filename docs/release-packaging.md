# Packaging HOME NET v1.6.0

`install-all.sh` по умолчанию использует `HOME_NET_BUNDLE_REF=v1.6.0`.
Явный override должен быть release tag `vX.Y.Z` или полным commit SHA из
40 строчных hex-символов. Branch refs, включая `main`, отклоняются до
скачивания payload и создания staging directory.

Manifest закрепляет Monitoring/LuCI на
`736798dbb673d76e220e6a5b9aa47dfdfa8f01f1`, а updater/init/config — на
`dc0a4edfee6a57c8cf66b9d66bd54db4a6ce6505`. Сохраняется уже проверенный
updater с self-test; старый commit не изменяется. Monitoring передаёт exact ref
в archive bootstrap, LuCI устанавливается из этого архива. Оба ref в manifest
обязаны быть полными SHA. Failover остаётся на tag `v1.4.1`.
URL rollout policy намеренно следует `main`; архитектура и policy model не меняются.

CI suite `release-packaging` запускает реальный bundle installer с подставными
payload и записывает все fetch URL. Без параметра manifest скачивается из
`v1.6.0`; с явным `v1.6.0` — тоже из этого tag. Компоненты скачиваются только
из закреплённых SHA. Полный commit ref также поддерживается. Moving refs
bundle и компонентов отклоняются. Роутеры, tag и releases тест не изменяет.

Эта правка — новый commit после merge commit `dc0a4ed`. Tag на `dc0a4ed`
содержал бы исходный installer и не включал бы исправление. Для публикации
исправленного v1.6.0 требуется отдельно подтвердить новый release target,
содержащий packaging fix. v1.5.4 и старый merge commit не переписываются.
Настройку release immutability ещё нужно включить/проверить отдельно.
