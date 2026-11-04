'use strict';
'require view';
'require fs';
'require ui';
'require home-net.common as management';

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

        return E('div', {}, [
            management.render('VPN', data[0]),
            E('section', { 'class': 'cbi-section' }, [
                E('h3', {}, _('Secure VPN')),
                info,
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
                } }, _('Инициализировать хранилище'))
            ])
        ]);
    },
    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
