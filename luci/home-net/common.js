'use strict';
'require baseclass';
'require fs';
'require ui';
'require poll';

function parse(text) {
    var values = {};
    String(text || '').split('\n').forEach(function(line) {
        var at = line.indexOf('=');
        if (at > 0) values[line.slice(0, at)] = line.slice(at + 1);
    });
    return values;
}
function tone(value) {
    value = String(value || 'UNKNOWN');
    if (/^(OK|RUNNING|healthy|Connected|AUTO APPLY ALLOWED)$/.test(value)) return 'green';
    if (/FAIL|ERROR|INVALID|BLOCKED|UNAVAILABLE/.test(value)) return 'red';
    if (/INSTALLING|VERIFYING|PENDING|BACKUP|STANDBY|INTERVENTION/.test(value)) return 'blue';
    return 'yellow';
}
var palette = {green:'#247333',yellow:'#996000',red:'#b01f24',blue:'#165fa3'};
function badge(value) { return E('strong', {style:'color:'+palette[tone(value)]}, value || 'UNKNOWN'); }
function row(label,value) { return E('div',{style:'padding:4px 0'},[E('span',{},label+': '), E('span',{},value || 'unknown')]); }
function block(title,children) { return E('section',{style:'border:1px solid #ccc;border-radius:8px;padding:16px;margin:12px 0'},[E('h3',{},title)].concat(children)); }
function button(label,handler,disabled) { return E('button',{class:'btn cbi-button-action',click:handler,disabled:disabled || null},label); }
function execute(action,args) {
    return fs.exec('/usr/bin/home-net-management',[action].concat(args || [])).then(function(r){
        if(r.code !== 0) throw new Error(r.stderr || 'Operation failed');
        return r.stdout;
    }).catch(function(e){ui.addNotification(null,E('p',{},String(e)),'error');throw e;});
}
function notify(text){ui.addNotification(null,E('p',{},text),'info');}
function updatePage(s) {
    var preview = {}, details = E('div',{},'Check the latest release to load its action class.');
    var current=E('div'), progress=E('div',{},'No background installation recorded.'), jobStatus='NONE';
    function currentRows(){return [row('Installed version',s.BUNDLE_INSTALLED),row('Active version',s.BUNDLE_ACTIVE),badge(s.UPDATE_STATUS)];}
    current.replaceChildren.apply(current,currentRows());
    function decisionRows(){return [row('Latest release',s.LATEST_RELEASE),row('Release class',s.RELEASE_ACTION_CLASS),row('Release rollout',s.RELEASE_ROLLOUT),row('Roll out ring',s.UPDATE_RING),row('Auto-update capable',s.AUTO_UPDATE_CAPABLE),row('AutoApply',s.AUTO_APPLY_ALLOWED),badge(s.AUTO_APPLY_STATE),row('Policy',s.ROLLOUT_POLICY_STATUS)];}
    var decision=E('div',{},decisionRows());
    function refreshDecision(){return fs.exec('/usr/bin/home-net-status',['status']).then(function(r){if(r.code)throw Error(r.stderr);s=parse(r.stdout);decision.replaceChildren.apply(decision,decisionRows());});}
    function refreshInstallation(){return Promise.all([refreshDecision(),fs.exec('/usr/bin/home-net-management',['install-status']),fs.exec('/usr/bin/home-net-management',['podkop-status'])]).then(function(results){
        var r=results[1];if(r.code)throw Error(r.stderr);var job=parse(r.stdout);jobStatus=job.STATUS || 'NONE';
        var labels={NONE:'No background installation recorded.',QUEUED:'Installation queued',RUNNING:'Installation in progress',SUCCEEDED:'Installation completed',FAILED:'Installation failed; check Logs and current version',INTERRUPTED:'Installation worker interrupted; check Logs and current version'};
        progress.replaceChildren(E('p',{},labels[jobStatus] || 'Installation state unknown'),row('Target',job.TARGET));
        current.replaceChildren.apply(current,currentRows());
        r=results[2];if(r.code)throw Error(r.stderr);var podkopJob=parse(r.stdout);podkopJobStatus=podkopJob.STATUS || 'NONE';
        var podkopLabels={NONE:'No Podkop update recorded.',QUEUED:'Podkop update queued',RUNNING:'Podkop update in progress',SUCCEEDED:'Podkop update completed',FAILED:'Podkop update failed; open update log for rollback details',INTERRUPTED:'Podkop update interrupted; check version and update log'};
        podkopProgress.replaceChildren(E('p',{},podkopLabels[podkopJobStatus] || 'Podkop update state unknown'),row('Target',podkopJob.TARGET));
        podkopCurrent=s.PODKOP_VERSION || podkopJob.CURRENT_VERSION || podkopCurrent;
        podkopDetails.replaceChildren(row('Current version',podkopCurrent),row('Latest version',podkopTarget));
        var busy=/^(QUEUED|RUNNING)$/.test(jobStatus) || /^(QUEUED|RUNNING)$/.test(podkopJobStatus);
        install.disabled=busy || !/^(SAFE|CONTROLLED)$/.test(preview.CLASS);
        podkopInstall.disabled=busy || !podkopTarget || String(podkopCurrent).replace(/^v/,'')===String(podkopTarget).replace(/^v/,'');
    });}
    var install = button('Install latest release',function(){
        if(!preview.TARGET || !/^(SAFE|CONTROLLED)$/.test(preview.CLASS)) return;
        ui.showModal('Confirm HOME NET installation',[
            row('Current',s.BUNDLE_INSTALLED),row('Target',preview.TARGET),row('Action class',preview.CLASS),
            E('p',{},'Backup → preflight and health → install → fresh health → activation. Git rollout governs automatic operations; this is an explicit manual operation.'),
            E('p',{},preview.CLASS === 'CONTROLLED' ? 'CONTROLLED requires working WAN, alternate VPN, and recovery coordination. The updater will check these conditions.' : 'Safety checks cannot be bypassed.'),
            button('Cancel',function(){ui.hideModal();}),
            button('Confirm installation',function(){ui.hideModal(); install.disabled=true;return execute('install-latest',[preview.TARGET]).then(function(text){notify(text);return refreshInstallation();}).catch(function(){install.disabled=false;});})
        ]);
    },true);
    function check(){return execute('preview').then(function(text){preview=parse(text);details.replaceChildren(row('Target',preview.TARGET),row('Release class',preview.CLASS));install.disabled=/^(QUEUED|RUNNING)$/.test(jobStatus) || /^(QUEUED|RUNNING)$/.test(podkopJobStatus) || !/^(SAFE|CONTROLLED)$/.test(preview.CLASS);if(preview.CLASS === 'CRITICAL')details.appendChild(E('p',{},'Manual intervention required'));});}
    var podkopTarget=null, podkopCurrent=s.PODKOP_VERSION, podkopJobStatus='NONE', podkopDetails=E('div',{},row('Current version',s.PODKOP_VERSION));
    var podkopProgress=E('div',{},'No Podkop update recorded.'), podkopLog=E('pre',{style:'max-height:400px;overflow:auto;white-space:pre-wrap'},'');
    var podkopInstall=button('Update Podkop',function(){
        if(!podkopTarget)return;
        if(!window.confirm('Update Podkop to '+podkopTarget+'? Backup, checksums, dependency preflight, protected configuration checks and fresh health are required. Rollback packages must be available.'))return;
        podkopInstall.disabled=true;
        return execute('podkop-update',[podkopTarget]).then(function(text){notify(text);return refreshInstallation();}).catch(function(){return refreshInstallation().catch(function(){});});
    },true);
    poll.add(function(){return refreshInstallation().catch(function(){});},5);
    return E('div',{},[
        block('Current',[current,progress]),
        block('Release and decision',[decision,details,button('Check for update',function(){return fs.exec('/usr/bin/home-net-control',['update-check']).then(function(r){if(r.code)throw Error(r.stderr);return refreshDecision().then(check);}).catch(function(e){notify(String(e));});}),install]),
        block('Podkop',[podkopDetails,podkopProgress,button('Check Podkop update',function(){return execute('podkop-check').then(function(t){var p=parse(t);podkopTarget=p.LATEST;podkopCurrent=p.CURRENT;podkopInstall.disabled=/^(QUEUED|RUNNING)$/.test(jobStatus) || /^(QUEUED|RUNNING)$/.test(podkopJobStatus) || !/^v?[0-9]+\.[0-9]+\.[0-9]+$/.test(p.LATEST || '') || String(p.CURRENT).replace(/^v/,'')===String(p.LATEST).replace(/^v/,'');podkopDetails.replaceChildren(row('Current version',p.CURRENT),row('Latest version',p.LATEST));});}),podkopInstall,button('Show Podkop update log',function(){return execute('podkop-log').then(function(text){podkopLog.textContent=text;});}),podkopLog,E('p',{},'Podkop is independent of the HOME NET bundle. Installation fails closed if exact rollback assets, digests, dependencies or required configuration are unavailable.')])
    ]);
}
function settingsPage(values){
    function input(value,type){return E('input',{type:type || 'text',value:value || '',class:'cbi-input-text'});}
    var enabled=E('input',{type:'checkbox',checked:values.HOME_NET_AUTO_UPDATE_ENABLED === '1'});
    var mode=E('select',{},[E('option',{value:'check',selected:values.HOME_NET_UPDATE_MODE !== 'apply'},'Check only'),E('option',{value:'apply',selected:values.HOME_NET_UPDATE_MODE === 'apply'},'Allow apply')]);
    var time=input(values.HOME_NET_UPDATE_TIME || '02:00','time'),start=input(values.HOME_NET_UPDATE_WINDOW_START || '02:00','time'),end=input(values.HOME_NET_UPDATE_WINDOW_END || '04:00','time'),jitter=input(String(Math.floor(Number(values.HOME_NET_UPDATE_JITTER || 3600)/60)),'number');
    var any=E('input',{type:'checkbox',checked:!!values.HOME_NET_UPDATE_WINDOW_START && values.HOME_NET_UPDATE_WINDOW_START === values.HOME_NET_UPDATE_WINDOW_END});
    function windowMode(){start.disabled=end.disabled=any.checked;}
    any.addEventListener('change',windowMode);windowMode();
    jitter.min=0;jitter.max=1440;
    function field(label,widget){return E('label',{style:'display:block;margin:12px 0'},[E('span',{},label+' '),widget]);}
    return block('Automatic updates',[E('p',{},values.LOCAL_POLICY_CONFIGURED === '0' ? 'Compatibility mode: existing v1.6.0 capability/ring behavior remains active. Mode restrictions take effect after saving these settings.' : 'Local settings are configured.'),E('p',{},'These local restrictions can only deny automatic updates. Git policy, capability, ring and safety gates remain mandatory. This page does not edit ring or central policy.'),field('Enable automatic updates',enabled),field('Mode',mode),field('Update time',time),field('Any time window',any),field('Window start',start),field('Window end',end),field('Jitter (minutes)',jitter),E('p',{},'Any time window removes only the window restriction; Update time still sets the daily schedule. Git policy and safety gates remain mandatory. Windows crossing midnight are supported.'),button('Save local settings',function(){return execute('save-settings',[enabled.checked?'1':'0',mode.value,time.value,any.checked?'00:00':start.value,any.checked?'00:00':end.value,jitter.value]).then(notify);})]);
}
function logTone(line){
    if (/\b(ERROR|ERR|FAIL(?:ED)?)\b/i.test(line)) return '#b01f24';
    if (/\b(WARN(?:ING)?)\b/i.test(line)) return '#a85b00';
    if (/\bDEBUG\b/i.test(line)) return '#666666';
    if (/\b(INFO|OK)\b/i.test(line)) return '#247333';
    return 'inherit';
}
function logsPage(){
    function select(values){return E('select',{},values.map(function(v){return E('option',{value:v},v);}));}
    var component=select(['all','updater','monitoring','failover','podkop','sing-box','system']),severity=select(['all','info','warning','error']),limit=select(['100','50','250','500']),order=select(['Newest first','Oldest first']),refresh=select(['off','5','30','60']),out=E('pre',{style:'max-height:550px;overflow:auto;white-space:pre-wrap;word-break:break-word'},''),tick=0;
    function load(){return fs.exec('/usr/bin/home-net-status',['logs',component.value,severity.value,limit.value]).then(function(r){if(r.code)throw Error(r.stderr);var lines=(r.stdout || '').trim().split('\n');if(order.value==='Newest first')lines.reverse();out.replaceChildren.apply(out,lines.map(function(line){return E('div',{style:'color:'+logTone(line)},line);}));}).catch(function(e){out.textContent=String(e);});}
    poll.add(function(){tick++;if(refresh.value!=='off' && tick % Number(refresh.value)===0)return load();},1);
    var page=block('Logs',[row('Order','Newest first by default'),component,severity,limit,order,button('Refresh',load),E('span',{},' Auto refresh (seconds) '),refresh,button('Clear view',function(){out.textContent='';}),out,E('p',{},'Clear view never removes log files. Historical events do not imply a current failure.')]);load();return page;
}
function overview(s,problems){
    var components=[['System',s.SYSTEM?'OK':'UNKNOWN','settings'],['VPN',s.VPN_STATUS || (s.ACTIVE_IP?'Connected':'UNKNOWN'),'vpn'],['Podkop',s.PODKOP,'logs'],['Sing-box',s.SING_BOX,'logs'],['FakeIP',s.FAKEIP,'vpn'],['Monitoring',s.STATUS,'logs'],['Updates',s.UPDATE_STATUS,'updates']];
    var cards=components.map(function(c){return block(c[0],[badge(c[1]),row('Last check',s.LAST_CHECK),row('Problem',c[1]==='OK'||c[1]==='RUNNING'||c[1]==='Connected'?'none':s.LAST_ERROR || ('Current state: '+(c[1] || 'UNKNOWN'))),E('a',{href:L.url('admin/services/home-net/'+c[2])},'Details')]);});
    var actions=block('Manual actions',[['health','Check health'],['switch-main','Switch to main VPN'],['switch-backup','Switch to backup VPN'],['restart-podkop','Restart Podkop'],['restart-singbox','Restart Sing-box']].map(function(item){var action=item[0];return button(item[1],function(){if(!window.confirm('Run '+action+' on this local router?'))return;return fs.exec('/usr/bin/home-net-control',[action]).then(function(r){if(r.code)throw Error(r.stderr);notify(r.stdout);}).catch(function(e){notify(String(e));});});}));
    return E('div',{},[actions,E('p',{},'Local router: '+(s.HOSTNAME || 'unknown')+'. Open HOME NET on each of the four Cudy to manage that router; remote state is not inferred.'),E('div',{style:'display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:12px'},cards),block('Recent problems',[E('h4',{},'Active problems'),s.STATUS==='OK'?E('p',{},'No current health failure reported.'):badge(s.STATUS),row('Current reason',s.LAST_ERROR),E('h4',{},'Historical problems'),E('pre',{style:'white-space:pre-wrap;max-height:240px;overflow:auto;color:'+palette.yellow},problems || 'No recorded events')])]);
}
function vpnPage(s){return E('div',{},[block('VPN',[row('Active VPN',s.ACTIVE_VPN),row('Country',s.ACTIVE_COUNTRY),row('IP',s.ACTIVE_IP),badge(s.VPN_STATUS || 'UNKNOWN'),row('Backup tunnel','awg_backup'),row('Backup status',s.BACKUP_TUNNEL_STATUS),row('Main country',s.AWG_MAIN_COUNTRY),row('Backup country',s.AWG_BACKUP_COUNTRY),row('Main handshake age (seconds)',s.AWG_MAIN_HANDSHAKE_AGE),row('Backup handshake age (seconds)',s.AWG_BACKUP_HANDSHAKE_AGE)]),block('FakeIP / DNS',[badge(s.FAKEIP),row('Cache size',s.FAKEIP_CACHE_SIZE),row('Active error',s.FAKEIP === 'OK'?'none':s.FAKEIP_LAST_ERROR),row('Error type',s.FAKEIP_ERROR_TYPE),E('p',{},'Historical errors are listed separately on Overview and Logs. Unknown values are not treated as healthy.')])]);}
return baseclass.extend({parse:parse,tone:tone,logTone:logTone,load:function(){return Promise.all([fs.exec('/usr/bin/home-net-status',['status']),fs.exec('/usr/bin/home-net-status',['settings']),fs.exec('/usr/bin/home-net-status',['problems','100'])]);},render:function(page,data){var s=parse(data[0].stdout);return E('div',{},[E('h2',{},'HOME NET — '+page),page==='Updates'?updatePage(s):page==='Settings'?settingsPage(parse(data[1].stdout)):page==='Logs'?logsPage():page==='VPN'?vpnPage(s):overview(s,data[2].stdout)]);}});
