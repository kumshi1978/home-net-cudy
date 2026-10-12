const fs=require('fs'),assert=require('assert'),path=require('path');
const root=path.resolve(__dirname,'..');
const calls=[],polls=[];let releaseClass='SAFE',modal,workerStatus='NONE',installed='1.6.0',podkopWorkerStatus='NONE',podkopVersion='0.7.22';
function E(tag,attrs,children){return {tag,attrs:attrs || {},children:Array.isArray(children)?children:[children],disabled:attrs && attrs.disabled,value:attrs && attrs.value || (tag==='select' && children[0].attrs.value),checked:attrs && attrs.checked,replaceChildren(...c){this.children=c},appendChild(c){this.children.push(c)},addEventListener(name,fn){this.attrs[name]=fn}}}
const rpc={exec:async(bin,args)=>{calls.push({bin,args});if(args[0]==='install-latest')workerStatus='RUNNING';if(args[0]==='podkop-update')podkopWorkerStatus='RUNNING';const output={
 preview:'TARGET=v1.7.0\nCLASS='+releaseClass+'\n',
 'install-status':'STATUS='+workerStatus+'\nTARGET=v1.7.0\n',
 'podkop-status':'STATUS='+podkopWorkerStatus+'\nTARGET=0.7.24\nCURRENT_VERSION='+podkopVersion+'\n',
 'podkop-check':'CURRENT='+podkopVersion+'\nLATEST=0.7.24\n',
 'podkop-log':'ROLLBACK VERIFIED: fixture retained details',
 'podkop-update':'Podkop update started in the background. Refresh Updates for the result.\n',
 'install-latest':'Installation started in the background. Refresh Updates to check Installed/Active and health.\n',
 'save-settings':'Local restrictions saved; Git policy and safety gates remain mandatory.\n',
 logs:'OK\nInstallation completed\n<img src=x>',
 status:'BUNDLE_INSTALLED='+installed+'\nBUNDLE_ACTIVE='+installed+'\nPODKOP_VERSION='+podkopVersion+'\nUPDATE_STATUS=OK\nRELEASE_ROLLOUT=fleet\nAUTO_APPLY_ALLOWED=1\nAUTO_APPLY_STATE=AUTO APPLY ALLOWED\nROLLOUT_POLICY_STATUS=OK\n'};return {code:0,stdout:output[args[0]] || '',stderr:''}}};
const ui={showModal:(title,children)=>{modal=E('modal',{},children)},hideModal:()=>{},addNotification:()=>{}};
const source=fs.readFileSync(path.join(root,'luci/home-net/common.js'),'utf8');
const common=new Function('baseclass','fs','ui','poll','E','L','window',source)({extend:x=>x},rpc,ui,{add:fn=>polls.push(fn)},E,{url:x=>'/'+x},{confirm:()=>true});
function all(n){return !n||typeof n!=='object'?[]:[n].concat((n.children || []).flatMap(all))}
function find(tree,label){return all(tree).find(x=>x.tag==='button' && x.children.includes(label))}
const data=[{stdout:'BUNDLE_INSTALLED=1.6.0\nBUNDLE_ACTIVE=1.6.0\nSTATUS=OK\nUPDATE_RING=stable\nRELEASE_ROLLOUT=manual\nAUTO_APPLY_ALLOWED=0\nAUTO_APPLY_STATE=WAITING FOR CANARY\n'},{stdout:''},{stdout:'Historical FakeIP event'}];
(async()=>{
 assert.equal(common.logTone('ERROR failure'),'#b01f24');assert.equal(common.logTone('WARN event'),'#a85b00');assert.equal(common.logTone('INFO OK'),'#247333');assert.equal(common.logTone('DEBUG trace'),'#666666');assert.equal(common.logTone('<img src=x>'),'inherit');
 assert.equal(common.tone('OK'),'green');assert.equal(common.tone('WAITING FOR CANARY'),'yellow');assert.equal(common.tone('WAITING FOR FLEET'),'yellow');assert.equal(common.tone('FAILED'),'red');assert.equal(common.tone('VERIFYING'),'blue');assert.equal(common.tone('UNKNOWN'),'yellow');
 let settings=common.render('Settings',data);let nodes=all(settings),inputs=nodes.filter(x=>x.tag==='input'),checkboxes=inputs.filter(x=>x.attrs.type==='checkbox');assert.equal(checkboxes[0].checked,false);assert.equal(inputs.find(x=>x.attrs.type==='time').value,'02:00');assert.equal(inputs.find(x=>x.attrs.type==='number').value,'60');
 checkboxes[1].checked=true;checkboxes[1].attrs.change();assert(inputs.filter(x=>x.attrs.type==='time').slice(1).every(x=>x.disabled));
 await find(settings,'Save local settings').attrs.click();assert(calls.some(c=>c.args.join(' ')==='save-settings 0 check 02:00 00:00 00:00 60'));
 for(const page of ['Overview','Updates','Logs','VPN','Settings'])assert.equal(common.render(page,data).tag,'div');
 let updates=common.render('Updates',data);assert(find(updates,'Install latest release').disabled);
 await find(updates,'Check for update').attrs.click();assert(!find(updates,'Install latest release').disabled);assert(JSON.stringify(updates).includes('AUTO APPLY ALLOWED'));assert(!JSON.stringify(updates).includes('WAITING FOR CANARY'));
 find(updates,'Install latest release').attrs.click();assert(modal);await find(modal,'Confirm installation').attrs.click();
 assert(calls.some(c=>c.bin==='/usr/bin/home-net-management' && c.args.join(' ')==='install-latest v1.7.0'));
 assert(!calls.some(c=>c.bin==='/usr/bin/home-net-update'));
 assert(JSON.stringify(updates).includes('Installation in progress'));assert(find(updates,'Install latest release').disabled);
 workerStatus='SUCCEEDED';installed='1.7.0';await polls[polls.length-1]();
 assert(JSON.stringify(updates).includes('Installation completed'));assert(JSON.stringify(updates).includes('1.7.0'));
 workerStatus='FAILED';await polls[polls.length-1]();assert(JSON.stringify(updates).includes('Installation failed'));
 await find(updates,'Check Podkop update').attrs.click();assert(!find(updates,'Update Podkop').disabled);
 await find(updates,'Update Podkop').attrs.click();assert(calls.some(c=>c.args.join(' ')==='podkop-update 0.7.24'));
 assert(JSON.stringify(updates).includes('Podkop update in progress'));assert(find(updates,'Update Podkop').disabled);assert(find(updates,'Install latest release').disabled);
 podkopWorkerStatus='SUCCEEDED';podkopVersion='0.7.24';await polls[polls.length-1]();assert(JSON.stringify(updates).includes('Podkop update completed'));assert(find(updates,'Update Podkop').disabled);
 podkopWorkerStatus='FAILED';podkopVersion='0.7.22';await polls[polls.length-1]();assert(JSON.stringify(updates).includes('Podkop update failed'));assert(JSON.stringify(updates).includes('0.7.22'));
 await find(updates,'Show Podkop update log').attrs.click();assert(JSON.stringify(updates).includes('ROLLBACK VERIFIED'));
 releaseClass='CRITICAL';updates=common.render('Updates',data);await find(updates,'Check for update').attrs.click();assert(find(updates,'Install latest release').disabled);
 const acl=JSON.parse(fs.readFileSync(path.join(root,'luci/acl.d/luci-app-home-net.json')));
 assert(!acl['luci-app-home-net'].read.file['/usr/bin/home-net-management']);
 assert.deepEqual(Object.keys(acl['luci-app-home-net'].write.file).sort(),['/usr/bin/home-net-control','/usr/bin/home-net-management']);
 const menu=JSON.parse(fs.readFileSync(path.join(root,'luci/menu.d/luci-app-home-net.json')));
 for(const p of ['overview','updates','logs','vpn','settings'])assert(menu['admin/services/home-net/'+p]);
 for(const file of ['status','updates','logs','vpn','settings'])new Function('view','management',fs.readFileSync(path.join(root,'luci/view/home-net/'+file+'.js'),'utf8'))({extend:x=>x},common);
 // Exercise the same UI actions in both languages; transport arguments stay English.
 for(const language of ['ru','ru-RU','en','de','']){
  const russian=/^ru/.test(language),localPolls=[],confirmations=[],notices=[];
  const links=[{textContent:'Updates',getAttribute:()=>'/admin/services/home-net/updates'},
   {textContent:'Logs',getAttribute:()=>'/admin/services/another-app/logs'},
   {textContent:'Logs',getAttribute:()=>'/admin/services/home-net-other/logs'}];
  const observers=[];
  const localized=new Function('baseclass','fs','ui','poll','E','L','window','document','MutationObserver',source)(
   {extend:x=>x},rpc,{...ui,addNotification:(a,n)=>notices.push(n)},
   {add:fn=>localPolls.push(fn)},E,{url:x=>'/'+x},
   {confirm:text=>{confirmations.push(text);return true}},
   {documentElement:{lang:language},querySelectorAll:()=>links,querySelector:()=>({})},
   function(callback){this.observe=()=>observers.push(callback)});
  workerStatus='NONE';podkopWorkerStatus='NONE';podkopVersion='0.7.22';releaseClass='SAFE';
  const labels=russian?['Обзор','Обновления','Журналы','VPN','Настройки']:['Overview','Updates','Logs','VPN','Settings'];
  ['Overview','Updates','Logs','VPN','Settings'].forEach((page,i)=>assert(JSON.stringify(localized.render(page,data)).includes('HOME NET — '+labels[i])));
  assert.equal(links[0].textContent,russian?'Обновления':'Updates');assert.equal(links[1].textContent,'Logs');assert.equal(links[2].textContent,'Logs');
  if(russian){links.push({textContent:'Logs',getAttribute:()=>'/admin/services/home-net/logs'});observers[0]();assert.equal(links[3].textContent,'Журналы');assert.equal(observers.length,2);}
  let page=localized.render('Updates',data);
  await find(page,russian?'Проверить обновление Podkop':'Check Podkop update').attrs.click();
  await find(page,russian?'Обновить Podkop':'Update Podkop').attrs.click();
  assert(confirmations[0].includes(russian?'Обновить Podkop до 0.7.24?':'Update Podkop to 0.7.24?'));
  assert(calls.some(c=>c.args.join(' ')==='podkop-update 0.7.24'));
  assert(JSON.stringify(page).includes(russian?'Выполняется обновление Podkop':'Podkop update in progress'));
  assert(JSON.stringify(notices).includes(russian?'Обновление Podkop запущено в фоне.':'Podkop update started in the background.'));
  assert(find(page,russian?'Обновить Podkop':'Update Podkop').disabled);
  podkopWorkerStatus='FAILED';await localPolls[localPolls.length-1]();
  assert(JSON.stringify(page).includes(russian?'Ошибка обновления Podkop':'Podkop update failed'));
  await find(page,russian?'Показать журнал обновления Podkop':'Show Podkop update log').attrs.click();
  assert(JSON.stringify(page).includes('ROLLBACK VERIFIED: fixture retained details'));
  await find(page,russian?'Проверить обновления':'Check for update').attrs.click();
  find(page,russian?'Установить последний релиз':'Install latest release').attrs.click();
  await find(modal,russian?'Подтвердить установку':'Confirm installation').attrs.click();
  assert(JSON.stringify(page).includes(russian?'Выполняется установка':'Installation in progress'));
  const settings=localized.render('Settings',data);await find(settings,russian?'Сохранить локальные настройки':'Save local settings').attrs.click();
  const logs=localized.render('Logs',data);await find(logs,russian?'Обновить':'Refresh').attrs.click();
  const log=all(logs).find(n=>n.tag==='pre');assert.deepEqual(log.children.map(n=>n.children[0]),['<img src=x>','Installation completed','OK']);
  const selects=all(logs).filter(n=>n.tag==='select');assert.equal(selects[0].value,'all');assert.equal(selects[3].value,'Newest first');
  const history=localized.render('Overview',[data[0],data[1],{stdout:'Installation completed'}]);
  assert(all(history).some(n=>n.tag==='pre' && n.children[0]==='Installation completed'));
  assert.deepEqual(localized.parse('STATUS=OK\nCLASS=SAFE\n'),{STATUS:'OK',CLASS:'SAFE'});
 }
 console.log('PASS LuCI pages, Russian/English/fallback, untranslated logs/protocol, confirmation, progress and ACL');
})().catch(e=>{console.error(e);process.exitCode=1});
