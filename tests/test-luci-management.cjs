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
 console.log('PASS LuCI pages, palette, explicit confirmation, CRITICAL disabled, ACL separation and compatibility route');
})().catch(e=>{console.error(e);process.exitCode=1});
