'use strict';
'require baseclass';
'require fs';
'require ui';
'require poll';

// LuCI's theme sets html.lang from dispatcher.lang. No extra language package is required.
var russian = typeof document !== 'undefined' && document.documentElement &&
    /^ru(?:[-_]|$)/i.test(document.documentElement.lang || '');
var russianText = {
    "Overview": "Обзор",
    "Updates": "Обновления",
    "Logs": "Журналы",
    "Settings": "Настройки",
    "Current": "Текущее состояние",
    "Installed version": "Установленная версия",
    "Active version": "Активная версия",
    "Latest release": "Последний релиз",
    "Release class": "Класс релиза",
    "Release rollout": "Распространение релиза",
    "Roll out ring": "Группа обновления",
    "Auto-update capable": "Поддержка автообновления",
    "AutoApply": "Автоматическая установка",
    "Policy": "Политика",
    "Target": "Целевая версия",
    "Current version": "Текущая версия",
    "Latest version": "Последняя версия",
    "Action class": "Класс действия",
    "Release and decision": "Релиз и решение",
    "Install latest release": "Установить последний релиз",
    "Check for update": "Проверить обновления",
    "Check Podkop update": "Проверить обновление Podkop",
    "Update Podkop": "Обновить Podkop",
    "Show Podkop update log": "Показать журнал обновления Podkop",
    "Confirm HOME NET installation": "Подтверждение установки HOME NET",
    "Confirm installation": "Подтвердить установку",
    "Cancel": "Отмена",
    "Manual intervention required": "Требуется ручное вмешательство",
    "Safety checks cannot be bypassed.": "Проверки безопасности обязательны.",
    "Check the latest release to load its action class.": "Проверьте обновления, чтобы загрузить класс действия релиза.",
    "No background installation recorded.": "Фоновая установка ещё не запускалась.",
    "Installation queued": "Установка ожидает запуска",
    "Installation in progress": "Выполняется установка",
    "Installation completed": "Установка завершена",
    "Installation failed; check Logs and current version": "Ошибка установки; проверьте журналы и текущую версию",
    "Installation worker interrupted; check Logs and current version": "Процесс установки прерван; проверьте журналы и текущую версию",
    "Installation state unknown": "Состояние установки неизвестно",
    "No Podkop update recorded.": "Обновление Podkop ещё не запускалось.",
    "Podkop update queued": "Обновление Podkop ожидает запуска",
    "Podkop update in progress": "Выполняется обновление Podkop",
    "Podkop update completed": "Обновление Podkop завершено",
    "Podkop update failed; open update log for rollback details": "Ошибка обновления Podkop; сведения об откате доступны в журнале обновления",
    "Podkop update interrupted; check version and update log": "Обновление Podkop прервано; проверьте версию и журнал обновления",
    "Podkop update state unknown": "Состояние обновления Podkop неизвестно",
    "Backup → preflight and health → install → fresh health → activation. Git rollout governs automatic operations; this is an explicit manual operation.": "Резервная копия → предварительные проверки и проверка состояния → установка → новая проверка состояния → активация. Политика Git управляет автоматическими операциями; здесь установка запускается вручную.",
    "CONTROLLED requires working WAN, alternate VPN, and recovery coordination. The updater will check these conditions.": "Для класса CONTROLLED необходимы работающий WAN, резервный VPN и согласованный способ восстановления. Установщик проверит эти условия.",
    "Podkop is independent of the HOME NET bundle. Installation fails closed if exact rollback assets, digests, dependencies or required configuration are unavailable.": "Podkop обновляется отдельно от HOME NET. Установка запрещена, если недоступны пакеты для отката, контрольные суммы, зависимости или необходимая конфигурация.",
    "Check only": "Только проверка",
    "Allow apply": "Разрешить установку",
    "Automatic updates": "Автоматические обновления",
    "Enable automatic updates": "Включить автоматические обновления",
    "Mode": "Режим",
    "Update time": "Время обновления",
    "Any time window": "Без ограничения по окну времени",
    "Window start": "Начало окна",
    "Window end": "Конец окна",
    "Jitter (minutes)": "Случайная задержка (минуты)",
    "Save local settings": "Сохранить локальные настройки",
    "Local settings are configured.": "Локальные настройки заданы.",
    "Compatibility mode: existing v1.6.0 capability/ring behavior remains active. Mode restrictions take effect after saving these settings.": "Режим совместимости: действуют правила поддержки и группы обновления версии 1.6.0. Ограничения режима вступят в силу после сохранения настроек.",
    "These local restrictions can only deny automatic updates. Git policy, capability, ring and safety gates remain mandatory. This page does not edit ring or central policy.": "Локальные ограничения могут только запрещать автоматические обновления. Политика Git, поддержка автообновления, группа и проверки безопасности обязательны. Эта страница не изменяет группу или центральную политику.",
    "Any time window removes only the window restriction; Update time still sets the daily schedule. Git policy and safety gates remain mandatory. Windows crossing midnight are supported.": "Этот флажок снимает только ограничение окна времени; время обновления по-прежнему задаёт ежедневное расписание. Политика Git и проверки безопасности обязательны. Поддерживаются окна, пересекающие полночь.",
    "Local restrictions saved; Git policy and safety gates remain mandatory.": "Локальные ограничения сохранены; политика Git и проверки безопасности обязательны.",
    "Installation started in the background. Refresh Updates to check Installed/Active and health.": "Установка запущена в фоне. Обновите страницу «Обновления», чтобы проверить установленную и активную версии и состояние.",
    "Podkop update started in the background. Refresh Updates for the result.": "Обновление Podkop запущено в фоне. Обновите страницу «Обновления», чтобы увидеть результат.",
    "Order": "Порядок",
    "Newest first by default": "По умолчанию сначала новые",
    "Newest first": "Сначала новые",
    "Oldest first": "Сначала старые",
    "Refresh": "Обновить",
    " Auto refresh (seconds) ": " Автообновление (секунды) ",
    "Clear view": "Очистить экран",
    "Clear view never removes log files. Historical events do not imply a current failure.": "Очистка экрана не удаляет файлы журналов. Исторические события не означают текущую неисправность.",
    "all": "Все",
    "updater": "Обновление",
    "monitoring": "Мониторинг",
    "failover": "Переключение VPN",
    "system": "Система",
    "info": "Информация",
    "warning": "Предупреждения",
    "error": "Ошибки",
    "off": "Выключено",
    "System": "Система",
    "Monitoring": "Мониторинг",
    "Last check": "Последняя проверка",
    "Problem": "Проблема",
    "Details": "Подробнее",
    "Manual actions": "Ручные действия",
    "Check health": "Проверить состояние",
    "Switch to main VPN": "Переключить на основной VPN",
    "Switch to backup VPN": "Переключить на резервный VPN",
    "Restart Podkop": "Перезапустить Podkop",
    "Restart Sing-box": "Перезапустить Sing-box",
    "Recent problems": "Последние проблемы",
    "Active problems": "Текущие проблемы",
    "Historical problems": "Исторические проблемы",
    "Current reason": "Текущая причина",
    "No current health failure reported.": "Текущих ошибок состояния не обнаружено.",
    "No recorded events": "Нет записанных событий",
    "Active VPN": "Активный VPN",
    "Country": "Страна",
    "Backup tunnel": "Резервный туннель",
    "Backup status": "Состояние резервного туннеля",
    "Main country": "Страна основного VPN",
    "Backup country": "Страна резервного VPN",
    "Main handshake age (seconds)": "Время с последнего обмена основного VPN (секунды)",
    "Backup handshake age (seconds)": "Время с последнего обмена резервного VPN (секунды)",
    "Cache size": "Размер кэша",
    "Active error": "Текущая ошибка",
    "Error type": "Тип ошибки",
    "Historical errors are listed separately on Overview and Logs. Unknown values are not treated as healthy.": "Исторические ошибки показаны отдельно на страницах «Обзор» и «Журналы». Неизвестное состояние не считается исправным.",
    "Operation failed": "Ошибка операции",
    "unknown": "Неизвестно",
    "UNKNOWN": "Неизвестно",
    "none": "Нет",
    "OK": "В норме",
    "RUNNING": "Работает",
    "Connected": "Подключён",
    "FAILED": "Ошибка",
    "INSTALLING": "Установка",
    "VERIFYING": "Проверка",
    "PENDING": "Ожидание",
    "BACKUP": "Резервный",
    "STANDBY": "Ожидание",
    "UNAVAILABLE": "Недоступно",
    "AUTO APPLY ALLOWED": "Автоматическая установка разрешена",
    "POLICY BLOCKED": "Установка запрещена политикой",
    "WAITING FOR CANARY": "Ожидание проверки canary",
    "WAITING FOR FLEET": "Ожидание распространения",
    "MISMATCH": "Несоответствие",
    "manual": "Вручную",
    "canary": "Canary",
    "fleet": "Все устройства",
    "stable": "Стабильная",
    "SAFE": "Безопасный (SAFE)",
    "CONTROLLED": "Контролируемый (CONTROLLED)",
    "CRITICAL": "Критический (CRITICAL)",
    "Update Podkop to %s? Backup, checksums, dependency preflight, protected configuration checks and fresh health are required. Rollback packages must be available.": "Обновить Podkop до %s? Обязательны резервная копия, контрольные суммы, проверка зависимостей, защищённой конфигурации и новая проверка состояния. Пакеты для отката должны быть доступны.",
    "Run %s on this local router?": "Выполнить действие «%s» на этом роутере?",
    "Current state: ": "Текущее состояние: ",
    "Local router: ": "Локальный роутер: ",
    ". Open HOME NET on each of the four Cudy to manage that router; remote state is not inferred.": ". Для управления каждым из четырёх Cudy откройте HOME NET на соответствующем роутере; состояние других устройств здесь не определяется."
};
function tr(text) {
    return russian && Object.prototype.hasOwnProperty.call(russianText, text) ? russianText[text] : text;
}
var navigationObserved = false;
function localizeNavigation() {
    if (!russian || typeof document.querySelectorAll !== 'function') return;
    var prefix = L.url('admin/services/home-net');
    function translateLinks() {
        document.querySelectorAll('#tabmenu a[href], #topmenu a[href]').forEach(function(link) {
            var href = link.getAttribute('href') || '', title = link.textContent.trim();
            if ((href === prefix || href.indexOf(prefix + '/') === 0) &&
                /^(Overview|Updates|Logs|Settings)$/.test(title)) link.textContent = tr(title);
        });
    }
    translateLinks();
    // LuCI can populate its navigation after the view has rendered.
    if (!navigationObserved && typeof MutationObserver !== 'undefined') {
        ['#tabmenu', '#topmenu'].forEach(function(selector) {
            var menu = document.querySelector(selector);
            if (menu) new MutationObserver(translateLinks).observe(menu, {childList:true, subtree:true});
        });
        navigationObserved = true;
    }
}
// Translate presentation text only; attributes, protocol values and log lines stay intact.
function element(tag, attrs, children) {
    function translated(child) { return typeof child === 'string' ? tr(child) : child; }
    return E(tag, attrs, Array.isArray(children) ? children.map(translated) : translated(children));
}

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
function badge(value) { return element('strong', {style:'color:'+palette[tone(value)]}, value || 'UNKNOWN'); }
function row(label,value) { return element('div',{style:'padding:4px 0'},[element('span',{},tr(label)+': '), E('span',{},tr(value || 'unknown'))]); }
function block(title,children) { return element('section',{style:'border:1px solid #ccc;border-radius:8px;padding:16px;margin:12px 0'},[element('h3',{},title)].concat(children)); }
function button(label,handler,disabled) { return element('button',{class:'btn cbi-button-action',click:handler,disabled:disabled || null},label); }
function execute(action,args) {
    return fs.exec('/usr/bin/home-net-management',[action].concat(args || [])).then(function(r){
        if(r.code !== 0) throw new Error(r.stderr || 'Operation failed');
        return r.stdout;
    }).catch(function(e){ui.addNotification(null,element('p',{},String(e)),'error');throw e;});
}
function notify(text){text=tr(String(text).trim());ui.addNotification(null,element('p',{},text),'info');}
function updatePage(s) {
    var preview = {}, details = element('div',{},'Check the latest release to load its action class.');
    var current=element('div'), progress=element('div',{},'No background installation recorded.'), jobStatus='NONE';
    function currentRows(){return [row('Installed version',s.BUNDLE_INSTALLED),row('Active version',s.BUNDLE_ACTIVE),badge(s.UPDATE_STATUS)];}
    current.replaceChildren.apply(current,currentRows());
    function decisionRows(){return [row('Latest release',s.LATEST_RELEASE),row('Release class',s.RELEASE_ACTION_CLASS),row('Release rollout',s.RELEASE_ROLLOUT),row('Roll out ring',s.UPDATE_RING),row('Auto-update capable',s.AUTO_UPDATE_CAPABLE),row('AutoApply',s.AUTO_APPLY_ALLOWED),badge(s.AUTO_APPLY_STATE),row('Policy',s.ROLLOUT_POLICY_STATUS)];}
    var decision=element('div',{},decisionRows());
    function refreshDecision(){return fs.exec('/usr/bin/home-net-status',['status']).then(function(r){if(r.code)throw Error(r.stderr);s=parse(r.stdout);decision.replaceChildren.apply(decision,decisionRows());});}
    function refreshInstallation(){return Promise.all([refreshDecision(),fs.exec('/usr/bin/home-net-management',['install-status']),fs.exec('/usr/bin/home-net-management',['podkop-status'])]).then(function(results){
        var r=results[1];if(r.code)throw Error(r.stderr);var job=parse(r.stdout);jobStatus=job.STATUS || 'NONE';
        var labels={NONE:'No background installation recorded.',QUEUED:'Installation queued',RUNNING:'Installation in progress',SUCCEEDED:'Installation completed',FAILED:'Installation failed; check Logs and current version',INTERRUPTED:'Installation worker interrupted; check Logs and current version'};
        progress.replaceChildren(element('p',{},labels[jobStatus] || 'Installation state unknown'),row('Target',job.TARGET));
        current.replaceChildren.apply(current,currentRows());
        r=results[2];if(r.code)throw Error(r.stderr);var podkopJob=parse(r.stdout);podkopJobStatus=podkopJob.STATUS || 'NONE';
        var podkopLabels={NONE:'No Podkop update recorded.',QUEUED:'Podkop update queued',RUNNING:'Podkop update in progress',SUCCEEDED:'Podkop update completed',FAILED:'Podkop update failed; open update log for rollback details',INTERRUPTED:'Podkop update interrupted; check version and update log'};
        podkopProgress.replaceChildren(element('p',{},podkopLabels[podkopJobStatus] || 'Podkop update state unknown'),row('Target',podkopJob.TARGET));
        podkopCurrent=s.PODKOP_VERSION || podkopJob.CURRENT_VERSION || podkopCurrent;
        podkopDetails.replaceChildren(row('Current version',podkopCurrent),row('Latest version',podkopTarget));
        var busy=/^(QUEUED|RUNNING)$/.test(jobStatus) || /^(QUEUED|RUNNING)$/.test(podkopJobStatus);
        install.disabled=busy || !/^(SAFE|CONTROLLED)$/.test(preview.CLASS);
        podkopInstall.disabled=busy || !podkopTarget || String(podkopCurrent).replace(/^v/,'')===String(podkopTarget).replace(/^v/,'');
    });}
    var install = button('Install latest release',function(){
        if(!preview.TARGET || !/^(SAFE|CONTROLLED)$/.test(preview.CLASS)) return;
        ui.showModal(tr('Confirm HOME NET installation'),[
            row('Current',s.BUNDLE_INSTALLED),row('Target',preview.TARGET),row('Action class',preview.CLASS),
            element('p',{},'Backup → preflight and health → install → fresh health → activation. Git rollout governs automatic operations; this is an explicit manual operation.'),
            element('p',{},preview.CLASS === 'CONTROLLED' ? 'CONTROLLED requires working WAN, alternate VPN, and recovery coordination. The updater will check these conditions.' : 'Safety checks cannot be bypassed.'),
            button('Cancel',function(){ui.hideModal();}),
            button('Confirm installation',function(){ui.hideModal(); install.disabled=true;return execute('install-latest',[preview.TARGET]).then(function(text){notify(text);return refreshInstallation();}).catch(function(){install.disabled=false;});})
        ]);
    },true);
    function check(){return execute('preview').then(function(text){preview=parse(text);details.replaceChildren(row('Target',preview.TARGET),row('Release class',preview.CLASS));install.disabled=/^(QUEUED|RUNNING)$/.test(jobStatus) || /^(QUEUED|RUNNING)$/.test(podkopJobStatus) || !/^(SAFE|CONTROLLED)$/.test(preview.CLASS);if(preview.CLASS === 'CRITICAL')details.appendChild(element('p',{},'Manual intervention required'));});}
    var podkopTarget=null, podkopCurrent=s.PODKOP_VERSION, podkopJobStatus='NONE', podkopDetails=element('div',{},row('Current version',s.PODKOP_VERSION));
    var podkopProgress=element('div',{},'No Podkop update recorded.'), podkopLog=element('pre',{style:'max-height:400px;overflow:auto;white-space:pre-wrap'},'');
    var podkopInstall=button('Update Podkop',function(){
        if(!podkopTarget)return;
        if(!window.confirm(tr('Update Podkop to %s? Backup, checksums, dependency preflight, protected configuration checks and fresh health are required. Rollback packages must be available.').replace('%s',podkopTarget)))return;
        podkopInstall.disabled=true;
        return execute('podkop-update',[podkopTarget]).then(function(text){notify(text);return refreshInstallation();}).catch(function(){return refreshInstallation().catch(function(){});});
    },true);
    poll.add(function(){return refreshInstallation().catch(function(){});},5);
    return element('div',{},[
        block('Current',[current,progress]),
        block('Release and decision',[decision,details,button('Check for update',function(){return fs.exec('/usr/bin/home-net-control',['update-check']).then(function(r){if(r.code)throw Error(r.stderr);return refreshDecision().then(check);}).catch(function(e){notify(String(e));});}),install]),
        block('Podkop',[podkopDetails,podkopProgress,button('Check Podkop update',function(){return execute('podkop-check').then(function(t){var p=parse(t);podkopTarget=p.LATEST;podkopCurrent=p.CURRENT;podkopInstall.disabled=/^(QUEUED|RUNNING)$/.test(jobStatus) || /^(QUEUED|RUNNING)$/.test(podkopJobStatus) || !/^v?[0-9]+\.[0-9]+\.[0-9]+$/.test(p.LATEST || '') || String(p.CURRENT).replace(/^v/,'')===String(p.LATEST).replace(/^v/,'');podkopDetails.replaceChildren(row('Current version',p.CURRENT),row('Latest version',p.LATEST));});}),podkopInstall,button('Show Podkop update log',function(){return execute('podkop-log').then(function(text){podkopLog.textContent=text;});}),podkopLog,element('p',{},'Podkop is independent of the HOME NET bundle. Installation fails closed if exact rollback assets, digests, dependencies or required configuration are unavailable.')])
    ]);
}
function settingsPage(values){
    function input(value,type){return element('input',{type:type || 'text',value:value || '',class:'cbi-input-text'});}
    var enabled=element('input',{type:'checkbox',checked:values.HOME_NET_AUTO_UPDATE_ENABLED === '1'});
    var mode=element('select',{},[element('option',{value:'check',selected:values.HOME_NET_UPDATE_MODE !== 'apply'},'Check only'),element('option',{value:'apply',selected:values.HOME_NET_UPDATE_MODE === 'apply'},'Allow apply')]);
    var time=input(values.HOME_NET_UPDATE_TIME || '02:00','time'),start=input(values.HOME_NET_UPDATE_WINDOW_START || '02:00','time'),end=input(values.HOME_NET_UPDATE_WINDOW_END || '04:00','time'),jitter=input(String(Math.floor(Number(values.HOME_NET_UPDATE_JITTER || 3600)/60)),'number');
    var any=element('input',{type:'checkbox',checked:!!values.HOME_NET_UPDATE_WINDOW_START && values.HOME_NET_UPDATE_WINDOW_START === values.HOME_NET_UPDATE_WINDOW_END});
    function windowMode(){start.disabled=end.disabled=any.checked;}
    any.addEventListener('change',windowMode);windowMode();
    jitter.min=0;jitter.max=1440;
    function field(label,widget){return element('label',{style:'display:block;margin:12px 0'},[element('span',{},tr(label)+' '),widget]);}
    return block('Automatic updates',[element('p',{},values.LOCAL_POLICY_CONFIGURED === '0' ? 'Compatibility mode: existing v1.6.0 capability/ring behavior remains active. Mode restrictions take effect after saving these settings.' : 'Local settings are configured.'),element('p',{},'These local restrictions can only deny automatic updates. Git policy, capability, ring and safety gates remain mandatory. This page does not edit ring or central policy.'),field('Enable automatic updates',enabled),field('Mode',mode),field('Update time',time),field('Any time window',any),field('Window start',start),field('Window end',end),field('Jitter (minutes)',jitter),element('p',{},'Any time window removes only the window restriction; Update time still sets the daily schedule. Git policy and safety gates remain mandatory. Windows crossing midnight are supported.'),button('Save local settings',function(){return execute('save-settings',[enabled.checked?'1':'0',mode.value,time.value,any.checked?'00:00':start.value,any.checked?'00:00':end.value,jitter.value]).then(notify);})]);
}
function logTone(line){
    if (/\b(ERROR|ERR|FAIL(?:ED)?)\b/i.test(line)) return '#b01f24';
    if (/\b(WARN(?:ING)?)\b/i.test(line)) return '#a85b00';
    if (/\bDEBUG\b/i.test(line)) return '#666666';
    if (/\b(INFO|OK)\b/i.test(line)) return '#247333';
    return 'inherit';
}
function logsPage(){
    function select(values){return element('select',{},values.map(function(v){return element('option',{value:v},v);}));}
    var component=select(['all','updater','monitoring','failover','podkop','sing-box','system']),severity=select(['all','info','warning','error']),limit=select(['100','50','250','500']),order=select(['Newest first','Oldest first']),refresh=select(['off','5','30','60']),out=element('pre',{style:'max-height:550px;overflow:auto;white-space:pre-wrap;word-break:break-word'},''),tick=0;
    function load(){return fs.exec('/usr/bin/home-net-status',['logs',component.value,severity.value,limit.value]).then(function(r){if(r.code)throw Error(r.stderr);var lines=(r.stdout || '').trim().split('\n');if(order.value==='Newest first')lines.reverse();out.replaceChildren.apply(out,lines.map(function(line){return E('div',{style:'color:'+logTone(line)},line);}));}).catch(function(e){out.textContent=String(e);});}
    poll.add(function(){tick++;if(refresh.value!=='off' && tick % Number(refresh.value)===0)return load();},1);
    var page=block('Logs',[row('Order','Newest first by default'),component,severity,limit,order,button('Refresh',load),element('span',{},' Auto refresh (seconds) '),refresh,button('Clear view',function(){out.textContent='';}),out,element('p',{},'Clear view never removes log files. Historical events do not imply a current failure.')]);load();return page;
}
function overview(s,problems){
    var components=[['System',s.SYSTEM?'OK':'UNKNOWN','settings'],['VPN',s.VPN_STATUS || (s.ACTIVE_IP?'Connected':'UNKNOWN'),'vpn'],['Podkop',s.PODKOP,'logs'],['Sing-box',s.SING_BOX,'logs'],['FakeIP',s.FAKEIP,'vpn'],['Monitoring',s.STATUS,'logs'],['Updates',s.UPDATE_STATUS,'updates']];
    var cards=components.map(function(c){return block(c[0],[badge(c[1]),row('Last check',s.LAST_CHECK),row('Problem',c[1]==='OK'||c[1]==='RUNNING'||c[1]==='Connected'?'none':s.LAST_ERROR || (tr('Current state: ')+tr(c[1] || 'UNKNOWN'))),element('a',{href:L.url('admin/services/home-net/'+c[2])},'Details')]);});
    var actions=block('Manual actions',[['health','Check health'],['switch-main','Switch to main VPN'],['switch-backup','Switch to backup VPN'],['restart-podkop','Restart Podkop'],['restart-singbox','Restart Sing-box']].map(function(item){var action=item[0];return button(item[1],function(){if(!window.confirm(tr('Run %s on this local router?').replace('%s',tr(item[1]))))return;return fs.exec('/usr/bin/home-net-control',[action]).then(function(r){if(r.code)throw Error(r.stderr);notify(r.stdout);}).catch(function(e){notify(String(e));});});}));
    return element('div',{},[actions,element('p',{},tr('Local router: ')+(s.HOSTNAME || tr('unknown'))+tr('. Open HOME NET on each of the four Cudy to manage that router; remote state is not inferred.')),element('div',{style:'display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:12px'},cards),block('Recent problems',[element('h4',{},'Active problems'),s.STATUS==='OK'?element('p',{},'No current health failure reported.'):badge(s.STATUS),row('Current reason',s.LAST_ERROR),element('h4',{},'Historical problems'),E('pre',{style:'white-space:pre-wrap;max-height:240px;overflow:auto;color:'+palette.yellow},problems || tr('No recorded events'))])]);
}
function vpnPage(s){return element('div',{},[block('VPN',[row('Active VPN',s.ACTIVE_VPN),row('Country',s.ACTIVE_COUNTRY),row('IP',s.ACTIVE_IP),badge(s.VPN_STATUS || 'UNKNOWN'),row('Backup tunnel','awg_backup'),row('Backup status',s.BACKUP_TUNNEL_STATUS),row('Main country',s.AWG_MAIN_COUNTRY),row('Backup country',s.AWG_BACKUP_COUNTRY),row('Main handshake age (seconds)',s.AWG_MAIN_HANDSHAKE_AGE),row('Backup handshake age (seconds)',s.AWG_BACKUP_HANDSHAKE_AGE)]),block('FakeIP / DNS',[badge(s.FAKEIP),row('Cache size',s.FAKEIP_CACHE_SIZE),row('Active error',s.FAKEIP === 'OK'?'none':s.FAKEIP_LAST_ERROR),row('Error type',s.FAKEIP_ERROR_TYPE),element('p',{},'Historical errors are listed separately on Overview and Logs. Unknown values are not treated as healthy.')])]);}
return baseclass.extend({parse:parse,tone:tone,logTone:logTone,load:function(){return Promise.all([fs.exec('/usr/bin/home-net-status',['status']),fs.exec('/usr/bin/home-net-status',['settings']),fs.exec('/usr/bin/home-net-status',['problems','100'])]);},render:function(page,data){localizeNavigation();var s=parse(data[0].stdout);return element('div',{},[element('h2',{},'HOME NET — '+tr(page)),page==='Updates'?updatePage(s):page==='Settings'?settingsPage(parse(data[1].stdout)):page==='Logs'?logsPage():page==='VPN'?vpnPage(s):overview(s,data[2].stdout)]);}});
