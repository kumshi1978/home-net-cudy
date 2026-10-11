const fs=require('fs'),assert=require('assert'),path=require('path');
const root=path.resolve(__dirname,'..');
const calls=[],polls=[];let releaseClass='SAFE',modal;
function E(tag,attrs,children){return {tag,attrs:attrs || {},children:Array.isArray(children)?children:[children],disabled:attrs && attrs.disabled,replaceChildren(...c){this.children=c},appendChild(c){this.children.push(c)}}}
const rpc={exec:async(bin,args)=>{calls.push({bin,args});return {code:0,stdout:args[0]==='preview'?'TARGET=v1.7.0\nCLASS='+releaseClass+'\n':args[0]==='status'?'RELEASE_ROLLOUT=fleet\nAUTO_APPLY_ALLOWED=1\nAUTO_APPLY_STATE=AUTO APPLY ALLOWED\nROLLOUT_POLICY_STATUS=OK\n':'',stderr:''}}};
const ui={showModal:(title,children)=>{modal=E('modal',{},children)},hideModal:()=>{},addNotification:()=>{}};
const source=fs.readFileSync(path.join(root,'luci/home-net/common.js'),'utf8');
const common=new Function('baseclass','fs','ui','poll','E','L','window',source)({extend:x=>x},rpc,ui,{add:fn=>polls.push(fn)},E,{url:x=>'/'+x},{confirm:()=>true});
function all(n){return !n||typeof n!=='object'?[]:[n].concat((n.children || []).flatMap(all))}
function find(tree,label){return all(tree).find(x=>x.tag==='button' && x.children.includes(label))}
const data=[{stdout:'BUNDLE_INSTALLED=1.6.0\nBUNDLE_ACTIVE=1.6.0\nSTATUS=OK\nUPDATE_RING=stable\nRELEASE_ROLLOUT=manual\nAUTO_APPLY_ALLOWED=0\nAUTO_APPLY_STATE=WAITING FOR CANARY\n'},{stdout:''},{stdout:'Historical FakeIP event'}];
(async()=>{
 assert.equal(common.tone('OK'),'green');assert.equal(common.tone('WAITING FOR CANARY'),'yellow');assert.equal(common.tone('WAITING FOR FLEET'),'yellow');assert.equal(common.tone('FAILED'),'red');assert.equal(common.tone('VERIFYING'),'blue');assert.equal(common.tone('UNKNOWN'),'yellow');
 for(const page of ['Overview','Updates','Logs','VPN','Settings'])assert.equal(common.render(page,data).tag,'div');
 let updates=common.render('Updates',data);assert(find(updates,'Install latest release').disabled);
 await find(updates,'Check for update').attrs.click();assert(!find(updates,'Install latest release').disabled);assert(JSON.stringify(updates).includes('AUTO APPLY ALLOWED'));assert(!JSON.stringify(updates).includes('WAITING FOR CANARY'));
 find(updates,'Install latest release').attrs.click();assert(modal);await find(modal,'Confirm installation').attrs.click();
 assert(calls.some(c=>c.bin==='/usr/bin/home-net-management' && c.args.join(' ')==='install-latest v1.7.0'));
 assert(!calls.some(c=>c.bin==='/usr/bin/home-net-update'));
 releaseClass='CRITICAL';updates=common.render('Updates',data);await find(updates,'Check for update').attrs.click();assert(find(updates,'Install latest release').disabled);
 const acl=JSON.parse(fs.readFileSync(path.join(root,'luci/acl.d/luci-app-home-net.json')));
 assert(!acl['luci-app-home-net'].read.file['/usr/bin/home-net-management']);
 assert.deepEqual(Object.keys(acl['luci-app-home-net'].write.file).sort(),['/usr/bin/home-net-control','/usr/bin/home-net-management']);
 const menu=JSON.parse(fs.readFileSync(path.join(root,'luci/menu.d/luci-app-home-net.json')));
 for(const p of ['overview','updates','logs','vpn','settings'])assert(menu['admin/services/home-net/'+p]);
 for(const file of ['status','updates','logs','vpn','settings'])new Function('view','management',fs.readFileSync(path.join(root,'luci/view/home-net/'+file+'.js'),'utf8'))({extend:x=>x},common);
 console.log('PASS LuCI pages, palette, explicit confirmation, CRITICAL disabled, ACL separation and compatibility route');
})().catch(e=>{console.error(e);process.exitCode=1});