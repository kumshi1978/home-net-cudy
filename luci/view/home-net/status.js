'use strict';
'require view';
'require fs';
'require ui';

function parseStatus(text) {
    var out = {};
    String(text || '').split('\n').forEach(function(line) {
        var pos = line.indexOf('=');
        if (pos > 0)
            out[line.substring(0, pos)] = line.substring(pos + 1);
    });
    return out;
}

function statusClass(value) {
    if (value === 'OK' || value === 'RUNNING')
        return 'color:#2d8a34;font-weight:600';
    if (value === 'UNKNOWN' || value === 'SKIPPED')
        return 'color:#b26a00;font-weight:600';
    return 'color:#b32020;font-weight:600';
}

function valueOrDash(value) {
    return value || '—';
}

function age(value) {
    if (!value || value === 'unknown' || value === 'never')
        return valueOrDash(value);
    var n = Number(value);
    if (!isFinite(n))
        return value;
    if (n < 60) return n + ' s';
    if (n < 3600) return Math.floor(n / 60) + ' min';
    return Math.floor(n / 3600) + ' h ' + Math.floor((n % 3600) / 60) + ' min';
}

function row(label, value, styled) {
    return E('div', { 'style': 'display:flex;justify-content:space-between;gap:16px;padding:5px 0;border-bottom:1px solid #eee' }, [
        E('span', {}, label),
        E('span', { 'style': styled ? statusClass(value) : 'font-weight:600;text-align:right' }, valueOrDash(value))
    ]);
}

function card(title, rows) {
    return E('div', { 'style': 'border:1px solid #ddd;border-radius:8px;padding:12px 14px;min-width:260px;flex:1;background:#fff' }, [
        E('h4', { 'style': 'margin:0 0 8px 0' }, title)
    ].concat(rows));
}

return view.extend({
    load: function() {
        return Promise.all([
            fs.exec('/usr/bin/home-net-status', [ 'status' ]),
            fs.exec('/usr/bin/home-net-status', [ 'problems', '80' ]),
            fs.exec('/usr/bin/home-net-status', [ 'events', '80' ]),
            fs.exec('/usr/bin/home-net-status', [ 'healthlog', '80' ])
        ]);
    },

    handleAction: function(action) {
        var confirmations = {
            'switch-main': _('Switch Podkop to awg_main and restart Podkop?'),
            'switch-backup': _('Switch Podkop to awg_backup and restart Podkop?'),
            'restart-podkop': _('Restart Podkop now?'),
            'restart-singbox': _('Restart sing-box now?')
        };

        if (confirmations[action] && !window.confirm(confirmations[action]))
            return;

        ui.showModal(_('HOME NET'), [
            E('p', { 'class': 'spinning' }, _('Running action…'))
        ]);

        return fs.exec('/usr/bin/home-net-control', [ action ]).then(function(res) {
            ui.hideModal();
            if (res.code !== 0) {
                ui.addNotification(null, E('p', {}, res.stderr || _('Action failed')), 'error');
                return;
            }
            ui.addNotification(null, E('p', {}, res.stdout || _('Action completed')), 'info');
            window.setTimeout(function() { window.location.reload(); }, 1000);
        }).catch(function(err) {
            ui.hideModal();
            ui.addNotification(null, E('p', {}, String(err)), 'error');
        });
    },

    render: function(data) {
        var s = parseStatus(data[0].stdout);
        var logStyle = 'max-height:280px;overflow:auto;white-space:pre-wrap;word-break:break-word;background:#111;color:#ddd;padding:10px;border-radius:6px;font-size:12px';

        return E('div', {}, [
            E('h2', {}, _('HOME NET')),
            E('p', {}, _('Local monitoring and limited control for Podkop, sing-box and AmneziaWG.')),

            E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:12px;margin-bottom:16px' }, [
                card(_('Overall'), [
                    row(_('Health'), s.STATUS, true),
                    row(_('Podkop'), s.PODKOP, true),
                    row(_('sing-box'), s.SING_BOX, true),
                    row(_('FakeIP'), s.FAKEIP, true),
                    row(_('Service check'), s.SERVICE_CHECK, true),
                    row(_('Last check'), s.LAST_CHECK)
                ]),
                card(_('Network'), [
                    row(_('Active VPN'), s.ACTIVE_VPN),
                    row(_('VPN IP'), s.ACTIVE_IP),
                    row(_('VPN country'), s.ACTIVE_COUNTRY),
                    row(_('WAN IP'), s.WAN_IP),
                    row(_('WAN country'), s.WAN_COUNTRY)
                ]),
                card(_('VPN'), [
                    row(_('awg_main country'), s.AWG_MAIN_COUNTRY),
                    row(_('awg_main handshake'), age(s.AWG_MAIN_HANDSHAKE_AGE)),
                    row(_('awg_backup country'), s.AWG_BACKUP_COUNTRY),
                    row(_('awg_backup handshake'), age(s.AWG_BACKUP_HANDSHAKE_AGE))
                ]),
                card(_('Updates'), [
                    row(_('Update ring'), s.UPDATE_RING),
                    row(_('Auto-update capable'), s.AUTO_UPDATE_CAPABLE),
                    row(_('Latest release'), s.LATEST_RELEASE),
                    row(_('Release rollout'), s.RELEASE_ROLLOUT),
                    row(_('Auto-apply allowed'), s.AUTO_APPLY_ALLOWED),
                    row(_('Rollout state'), s.AUTO_APPLY_STATE),
                    row(_('Policy status'), s.ROLLOUT_POLICY_STATUS)
                ]),
                card(_('Versions'), [
                    row(_('Bundle installed'), s.BUNDLE_INSTALLED),
                    row(_('Bundle active'), s.BUNDLE_ACTIVE),
                    row(_('Update status'), s.UPDATE_STATUS, s.UPDATE_STATUS === 'OK'),
                    row(_('Monitoring'), s.MONITORING_VERSION),
                    row(_('Failover'), s.FAILOVER_VERSION),
                    row(_('Problems recorded'), s.PROBLEM_COUNT)
                ])
            ]),

            E('h3', {}, _('Actions')),
            E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:8px;margin-bottom:18px' }, [
                E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, 'handleAction', 'health') }, _('Check now')),
                E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, 'handleAction', 'update-check') }, _('Check update')),
                E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, 'handleAction', 'switch-main') }, _('Use awg_main')),
                E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, 'handleAction', 'switch-backup') }, _('Use awg_backup')),
                E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, 'handleAction', 'restart-podkop') }, _('Restart Podkop')),
                E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, 'handleAction', 'restart-singbox') }, _('Restart sing-box'))
            ]),

            E('h3', {}, _('Problems')),
            E('pre', { 'style': logStyle }, data[1].stdout || _('No recorded problems.')),

            E('h3', {}, _('Failover / health events')),
            E('pre', { 'style': logStyle }, data[2].stdout || _('No recent events.')),

            E('h3', {}, _('Health history')),
            E('pre', { 'style': logStyle }, data[3].stdout || _('No health history.'))
        ]);
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});
