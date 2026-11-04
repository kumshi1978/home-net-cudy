'use strict';
'require view';
'require fs';
'require ui';
'require rpc';
'require home-net.common as management';

var prepareUpload = rpc.declare({ object: 'home-net-vpn', method: 'prepare', params: ['deployment', 'country', 'ciphertext'] });

function status() {
    return fs.exec('/usr/bin/home-net-status', ['vpn-secure']).then(function(result) {
        if (result.code) throw new Error(_('Не удалось прочитать состояние secure VPN'));
        return management.parse(result.stdout);
    });
}

function showStatus(container, values) {
    function row(label, key) {
        var value = String(values[key] || '').replace(/^'|'$/g, '');
        return E('p', {}, [label, ' ', value || '—']);
    }
    container.replaceChildren(
        row(_('Router ID'), 'ROUTER_ID'),
        row(_('Криптографическая identity'), 'IDENTITY_STATUS'),
        row(_('Публичный recipient'), 'PUBLIC_RECIPIENT'),
        row(_('Транзакция'), 'TRANSACTION_STATE'),
        row(_('Блокировка'), 'TRANSACTION_LOCK')
    );
}

return view.extend({
    load: function() {
        return Promise.all([management.load(), status().catch(function() { return null; })]);
    },
    render: function(data) {
        var info = E('div');
        function refresh() {
            return status().then(function(values) { showStatus(info, values); });
        }
        function report() {
            ui.addNotification(null, E('p', {}, _('Операция secure VPN не выполнена')), 'error');
        }
        if (data[1]) showStatus(info, data[1]);
        else info.textContent = _('Состояние secure VPN недоступно');

        function rotationButton(label, action, warning) {
            return E('button', { 'class': 'btn', 'click': function(event) {
                if (!window.confirm(warning)) return;
                var button = event.currentTarget;
                button.disabled = true;
                return fs.exec('/usr/bin/home-net-management', [action])
                    .then(function(result) {
                        if (result.code) throw new Error();
                        if (action === 'vpn-rotation-stage') {
                            var recipient = String(result.stdout || '').trim();
                            if (!/^age1[023456789acdefghjklmnpqrstuvwxyz]{58}$/.test(recipient))
                                throw new Error();
                            ui.addNotification(null, E('p', {}, [_('Публичный recipient кандидата'), ' ', recipient]));
                        }
                        return refresh();
                    }).catch(report).then(function() { button.disabled = false; });
            } }, label);
        }

        var file = E('input', { type: 'file', accept: '.age' });
        var deployment = E('input', { type: 'text', maxlength: '64', placeholder: _('Идентификатор deployment') });
        var country = E('input', { type: 'text', maxlength: '2', placeholder: _('Код страны') });
        var upload = E('button', { 'class': 'btn', click: function() {
            var candidate = file.files[0];
            if (!candidate || !candidate.size || candidate.size > 65536 ||
                !/^[A-Za-z0-9._-]{1,64}$/.test(deployment.value) || !/^[A-Z]{2}$/.test(country.value)) {
                report();
                return;
            }
            if (!window.confirm(_('Загрузить зашифрованный профиль и подготовить неактивный слот?'))) return;
            var id = deployment.value;
            var expectedCountry = country.value;
            upload.disabled = true;
            return candidate.arrayBuffer().then(function(bytes) {
                var binary = '';
                var view = new Uint8Array(bytes);
                for (var offset = 0; offset < view.length; offset += 4096)
                    binary += String.fromCharCode.apply(null, view.subarray(offset, offset + 4096));
                return prepareUpload(id, expectedCountry, btoa(binary));
            }).then(function(result) {
                if (!result || result.status !== 'prepared') throw new Error();
                ui.addNotification(null, E('p', {}, _('Неактивный слот подготовлен')));
                return refresh();
            }).catch(report).then(function() { upload.disabled = false; file.value = ''; });
        } }, _('Загрузить и подготовить'));

        return E('div', {}, [
            management.render('VPN', data[0]),
            E('section', { 'class': 'cbi-section' }, [
                E('h3', {}, _('Secure VPN')),
                info,
                file, deployment, country, upload,
                rotationButton(_('Проверить профиль'), 'vpn-verify', _('Проверить подготовленный профиль?')),
                rotationButton(_('Переключить VPN'), 'vpn-promote', _('Переключить трафик на проверенный слот?')),
                rotationButton(_('Откатить VPN'), 'vpn-rollback', _('Восстановить предыдущий VPN и сохранённую конфигурацию?')),
                E('button', { 'class': 'btn', 'click': function() {
                    return refresh().catch(report);
                } }, _('Проверить identity')),
                E('button', { 'class': 'btn', 'click': function(event) {
                    if (!window.confirm(_('Инициализировать локальное хранилище ключей?'))) return;
                    var button = event.currentTarget;
                    button.disabled = true;
                    return fs.exec('/usr/bin/home-net-management', ['vpn-initialize'])
                        .then(function(result) {
                            if (result.code) throw new Error();
                            return refresh();
                        }).catch(report).then(function() { button.disabled = false; });
                } }, _('Инициализировать хранилище')),
                rotationButton(_('Создать ключ-кандидат'), 'vpn-rotation-stage',
                    _('Создать новый локальный ключ? Текущий ключ продолжит работать.')),
                rotationButton(_('Применить новый ключ'), 'vpn-rotation-promote',
                    _('Заменить текущий ключ? Старые .conf.age могут требовать прежний ключ. Его резервная копия останется на роутере.')),
                rotationButton(_('Вернуть прежний ключ'), 'vpn-rotation-rollback',
                    _('Восстановить прежний ключ? Для пакетов, зашифрованных на новый recipient, потребуется повторное шифрование.'))
            ])
        ]);
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
