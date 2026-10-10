# HOME NET v1.6.0 rollout-test: сценарий после merge PR #18

Это план будущей проверки, а не отчёт о выполнении. Merge, публикация v1.6.0,
изменение production policy и любые действия на роутерах требуют отдельной
команды оператора. Stable tag/release v1.5.4 сохраняется без изменений.
Предрелизный тест candidate описан отдельно в `HARDWARE_CANARY_1.6.0.md`.

## Условия допуска

1. Финальный head PR прошёл HOME NET CI: self-test, updater, installer safety,
   LuCI static, candidate packaging и component update policy. Конфликтов merge нет.
2. После отдельно подтверждённого merge зафиксирован exact merge commit.
   `VERSION` и `HOME_NET_BUNDLE_VERSION` равны `1.6.0`; Monitoring ref существует
   и зафиксирован точным commit. Состав failover остаётся `1.4.1`.
3. На всех участвующих Cudy установлен updater с новой rollout-моделью и явно
   настроены новые config keys. Updater из v1.5.4 не знает manual/canary/fleet,
   не выводит новые Gate и не защищается новой policy. Одного изменения config
   старого updater недостаточно. Миграция кода и config выполняется отдельно,
   с backup/rollback и сохранением production bundle state до публикации release.
4. Квартирный backup Cudy имеет `HOME_NET_ROLLOUT_RING='canary'`. Квартирный main
   и оба дачных Cudy имеют `HOME_NET_ROLLOUT_RING='stable'`. У подходящих Cudy:
   `HOME_NET_AUTO_UPDATE_CAPABLE='1'`. При capability=0 автоустановка запрещена.
   Существующий config installer не перезаписывает; роль нельзя предполагать
   по hostname или старому `HOME_NET_UPDATE_CANARY`.
5. Policy URL возвращён на
   `https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/rollout-policy.conf`.
   Локальные HTTP fixtures отключены. Компонентный updater проверен отдельно:
   он не подчиняется HOME NET rollout policy и не должен параллельно применять
   изменения во время теста.
6. У каждого устройства сохранены локальные backup и baseline: bundle installed/
   active/status, health, Podkop interface, WAN/default route, VPN, DNS/FakeIP,
   service status и доступность LuCI/SSH. Есть способ восстановления связи.
   Публичный отчёт содержит только обезличенные результаты, без секретов.

Перед публикацией подтвердить, что выполняются все условия. Если хотя бы один
роутер остаётся на legacy updater, его нельзя считать защищённым Stage 1/2.

## Доступность self-test

`home-net-update self-test` доступен начиная с v1.6.0. На штатном updater v1.5.4
команда отсутствует — это ожидаемое поведение, а не неисправность. Candidate
updater из PR #18 уже содержит команду даже при сохранённом state bundle v1.5.4;
наличие self-test определяется версией установленного кода updater.

```sh
home-net-update self-test
```

Ожидается `Self-test: 36 passed, 0 failed`, exit code 0. Команда офлайн, не читает
operator config и не меняет реальные state/cache/lock/backup. Она не доказывает
готовность runtime, конфигурации ring или фактическую установку release.

## Stage 1 — manual

Только после отдельного подтверждения подготовить policy:

```text
POLICY_SCHEMA='1'
RELEASE_TAG='v1.6.0'
ROLLOUT='manual'
```

Затем создать tag v1.6.0 на проверенном merge commit и опубликовать release
«v1.6.0 rollout-test». Для реального updater release должен иметь
`draft=false`, `prerelease=false` и быть latest stable. Draft/prerelease для этого
сценария не подходит: updater их отвергает. Даже с названием rollout-test это
настоящий опубликованный stable release, доступный legacy updater.

Безопасный порядок: сначала применить manual policy, затем публиковать release.
До публикации временное несовпадение policy tag и latest v1.5.4 даёт
`POLICY BLOCKED`; это ожидаемый fail-closed промежуток. После публикации tag и
состав release не изменять: дальнейшие stages меняют только mutable policy.

На каждом мигрированном роутере выполнить:

```sh
home-net-update check
home-net-update status
```

`check` не устанавливает bundle, но обновляет rollout cache и может записать
`UPDATE_AVAILABLE` в state. `status` показывает cache предыдущей проверки;
сам по себе он не скачивает актуальную policy.

| Ring | Latest | Policy | AutoApply | Gate |
| --- | --- | --- | ---: | --- |
| canary | v1.6.0 | OK | 0 | WAITING FOR CANARY |
| stable | v1.6.0 | OK | 0 | WAITING FOR CANARY |

Для baseline bundle v1.5.4 installed/active должны остаться `1.5.4`, обычно status
становится `UPDATE_AVAILABLE`, pending остаётся `none`. Existing PENDING_APPLY,
INSTALLING, VERIFYING и FAILED updater не заменяет на UPDATE_AVAILABLE.
Проверить LuCI → Services → HOME NET: latest, ring, rollout, AutoApply и Gate
соответствуют CLI. Оставить время для штатного daemon cycle и убедиться,
что ни canary, ни stable не начали installation.

Не использовать `home-net-update apply` для проверки manual gate: в новой модели
это явное операторское действие, которое обходит rollout policy. Команда `auto`
также может установить bundle и применяется только по отдельной команде.

## Stage 2 — canary

После успешного Stage 1 и отдельного разрешения изменить только policy:

```text
POLICY_SCHEMA='1'
RELEASE_TAG='v1.6.0'
ROLLOUT='canary'
```

Повторить `check` → `status` на canary и каждом stable. При capability=1:

| Ring | Latest | Policy | AutoApply | Gate |
| --- | --- | --- | ---: | --- |
| canary | v1.6.0 | OK | 1 | AUTO APPLY ALLOWED |
| stable | v1.6.0 | OK | 0 | WAITING FOR FLEET |

Для stable фактическая надпись updater — **WAITING FOR FLEET**.
WAITING FOR CANARY относится к Stage 1, когда rollout=manual.

Дождаться auto cycle canary. Default startup delay=300 s, jitter до 21600 s,
interval=86400 s; после продвижения policy уже работающий daemon может ждать
следующего interval. Это не обещание немедленной установки. Для управляемого
ускорения допустима отдельно разрешённая команда `home-net-update auto` только
на canary; stable не ускорять и не вызывать explicit apply.

Для текущего manifest `UPDATE_ACTION_CLASS='SAFE'` и `PENDING_ACTION='none'` после
нового здорового Monitoring cycle ожидаются:

```text
Installed: 1.6.0
Active:    1.6.0
Status:    OK
Pending:   none
Health:    OK
```

Проверить backup, updater log и новый завершённый health cycle с
`STATUS=OK`, `PODKOP=RUNNING`, `SING_BOX=RUNNING`, `FAKEIP=OK`, `SERVICE_CHECK=OK`.
Сверить DNS/FakeIP, VPN/handshake, WAN, routing и доступность SSH/LuCI с baseline.
В LuCI проверить read-only панели, версии, problems/events/history, Check now
и Check update. Switch/restart controls проверять только отдельным разрешённым
действием на canary, с подтверждением в UI и доказательством восстановления.

Повторно выполнить self-test 36/36 на установленном updater. Все stable должны
сохранить baseline installed/active и не иметь факта installation v1.6.0.
Задать и записать окно наблюдения canary до Stage 3; продолжительность не
считать подтверждённой без фактического времени начала/окончания и результатов.

AutoApply=1 — разрешение policy, а не результат установки. Ошибка installer,
health FAIL/UNKNOWN/timeout не подтверждает успешную активацию. Для CONTROLLED
действуют дополнительные runtime preflight/coordination checks. Для CRITICAL
ожидается staging и PENDING_APPLY с прежней Active version, без automatic reboot
или network restart; текущий SAFE release искусственно не превращать в CRITICAL.

## Stage 3 — fleet

Только после зафиксированного PASS canary и отдельного разрешения:

```text
POLICY_SCHEMA='1'
RELEASE_TAG='v1.6.0'
ROLLOUT='fleet'
```

Все подходящие Cudy с новым updater, допустимым ring и capability=1 получают:

| Ring | Latest | Policy | AutoApply | Gate |
| --- | --- | --- | ---: | --- |
| canary | v1.6.0 | OK | 1 | AUTO APPLY ALLOWED |
| stable | v1.6.0 | OK | 1 | AUTO APPLY ALLOWED |

После каждого штатного auto cycle сверить installed/active/status/health, backup
и LuCI с критериями Stage 2. Уже обновлённый canary повторно не устанавливает
тот же release. No downgrade: state новее latest не понижается.
Устройства с capability=0 остаются AUTO UPDATE DISABLED. Неверный config
завершает updater ошибкой, не создавая выдуманный Gate.

## Все фактические Gate

Значения взяты из `scripts/home-net-update` (`set_rollout_wait_state`,
`evaluate_rollout_policy`, `fetch_rollout_policy`, `show_status`).

| Gate | Когда выводится | AutoApply |
| --- | --- | ---: |
| AUTO APPLY ALLOWED | policy OK, capability=1; canary/canary либо fleet/любой допустимый ring | 1 |
| WAITING FOR CANARY | policy OK, capability=1, rollout=manual | 0 |
| WAITING FOR FLEET | policy OK, capability=1, rollout=canary, ring=stable | 0 |
| POLICY BLOCKED | policy недоступна, невалидна или tag не совпадает с latest | 0 |
| POLICY UNKNOWN | начальное состояние / нет читаемого rollout cache при status | 0 |
| AUTO UPDATE DISABLED | policy валидна и совпадает, но capability=0 | 0 |

При invalid/unavailable/mismatch policy BLOCKED сохраняется даже при capability=0:
disabled override применяется только после успешной проверки policy.
Поле `Policy` отдельно принимает UNKNOWN/UNAVAILABLE/INVALID/MISMATCH/OK;
это не дополнительные названия Gate. `Latest: unknown` и `Rollout: unknown`
также не Gate. При legacy config команда check не обновляет rollout cache;
старый cache нельзя считать доказательством текущего решения. При ошибке сети
до policy refresh cache может быть старым — сверять exit code, log и CHECKED_AT.

## Остановка продвижения и rollback

При неуспехе остановить дальнейшие stages. По отдельной команде вернуть
policy v1.6.0 в manual; это блокирует будущие auto apply после очередного fetch,
но не отменяет уже запущенный installer и не откатывает установленный bundle.
Сохранить обезличенные log/health/state и путь локального backup. Провести
операторское восстановление по baseline и компонентным backup; не редактировать
state вручную ради PASS. Не запускать повторный тест до подтверждения восстановления.

## Что зафиксировать в отчёте

- exact merge commit, tag/release и CI run URL;
- время и содержимое policy на каждом stage;
- ring/capability каждого устройства и версия реально установленного updater;
- Latest/Rollout/Policy/AutoApply/Gate после свежей проверки;
- installed/active/status/pending/health до и после;
- backup, изменения LuCI и результаты runtime checks;
- фактическое окно наблюдения, ошибки и rollback/restore evidence;
- неизменность tag/release v1.5.4. Старые результаты не переносить в новый отчёт.
