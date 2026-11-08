#!/usr/bin/python3
"""Persist only a verified inactive AWG slot. Invoked under the controller lock."""
import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

NETWORK=Path('/etc/config/network')
BACKUP=Path('/etc/home-net/vpn/transaction/backup/network.before-persist')
SLOTS=('awg_main','awg_backup','awg_backup2')
INTERFACE={'PrivateKey':'private_key','ListenPort':'listen_port',**{k:k.lower() for k in ('Jc','Jmin','Jmax','S1','S2','S3','S4','H1','H2','H3','H4','I1','I2','I3','I4','I5')}}
PEER={'PublicKey':'public_key','PresharedKey':'preshared_key','PersistentKeepalive':'persistent_keepalive','AdvancedSecurity':'advanced_security'}

def key(value):
    if len(base64.b64decode(value,validate=True))!=32:raise ValueError('invalid key')

def parse(conf):
    section=None;values={};sections=[]
    for raw in conf.decode('ascii').splitlines():
        line=raw.strip()
        if not line or line.startswith('#'):continue
        if line in ('[Interface]','[Peer]'):
            sections.append(line);section=line;continue
        if '=' not in line or not section:raise ValueError('invalid config')
        name,value=(x.strip() for x in line.split('=',1))
        if name in values or not value or any(c in value for c in ("'",'"','\n','\r')):raise ValueError('invalid field')
        if section=='[Interface]' and name not in INTERFACE:raise ValueError('invalid interface field')
        if section=='[Peer]' and name not in (*PEER,'Endpoint','AllowedIPs'):raise ValueError('invalid peer field')
        values[name]=value
    if sections!=['[Interface]','[Peer]'] or not {'PrivateKey','PublicKey','Endpoint','AllowedIPs'}<=values.keys():raise ValueError('missing field')
    for name in ('PrivateKey','PublicKey','PresharedKey'):
        if name in values:key(values[name])
    host,port=values['Endpoint'].rsplit(':',1);ipaddress.IPv4Address(host)
    if not port.isdigit() or not 1<=int(port)<=65535:raise ValueError('invalid endpoint')
    for address in values['AllowedIPs'].split(','):ipaddress.ip_network(address.strip(),strict=False)
    for name,value in values.items():
        if name not in ('PrivateKey','PublicKey','PresharedKey','Endpoint','AllowedIPs','AdvancedSecurity') and name not in ('I1','I2','I3','I4','I5'):
            if not value.isdigit():raise ValueError('invalid numeric field')
        if name.startswith('I') and name!='Interface' and not re.fullmatch(r'[A-Za-z0-9<>:_.,=+ /-]{1,2048}',value):raise ValueError('invalid obfuscation')
    return values

def uci(args,directory=None,input=None):
    command=['uci']
    if directory:command+=['-c',str(directory),'-t',str(Path(directory)/'.uci')]
    return subprocess.check_output(command+args,input=input,stderr=subprocess.DEVNULL,timeout=10)

def persist(slot,expected):
    if slot not in SLOTS or not re.fullmatch('[a-f0-9]{64}',expected):raise ValueError('invalid target')
    if NETWORK.is_symlink() or NETWORK.parent.is_symlink():raise ValueError('unsafe path')
    if uci(['changes','network']).strip():raise ValueError('uncommitted network changes')
    if uci(['-q','get','network.'+slot+'.proto']).strip()!=b'amneziawg':raise ValueError('invalid interface')
    conf=subprocess.check_output(['awg','showconf',slot],stderr=subprocess.DEVNULL,timeout=5).rstrip(b'\n')+b'\n'
    if hashlib.sha256(conf).hexdigest()!=expected:raise ValueError('runtime config changed')
    values=parse(conf);original=NETWORK.read_bytes()
    shown=uci(['-q','show','network']).decode()
    commands=[]
    # Descending indexes keep anonymous peer identifiers stable as they are removed.
    peers=[line.split('=',1)[0] for line in shown.splitlines() if line.endswith('=amneziawg_'+slot)]
    for peer in reversed(peers):commands.append('delete '+peer)
    for name,option in INTERFACE.items():
        if name in values:commands.append("set network."+slot+'.'+option+"='"+values[name]+"'")
        elif any(line.startswith('network.'+slot+'.'+option+'=') for line in shown.splitlines()):commands.append('delete network.'+slot+'.'+option)
    peer='network.home_net_'+slot
    if any(line.startswith(peer+'=') and line!=peer+'=amneziawg_'+slot for line in shown.splitlines()):raise ValueError('peer section collision')
    commands+=['set '+peer+'=amneziawg_'+slot,"set network."+slot+".auto='1'",'set '+peer+".route_allowed_ips='0'"]
    for name,option in PEER.items():
        if name in values:commands.append('set '+peer+'.'+option+"='"+values[name]+"'")
    host,port=values['Endpoint'].rsplit(':',1)
    commands+=['set '+peer+".endpoint_host='"+host+"'",'set '+peer+".endpoint_port='"+port+"'"]
    for address in values['AllowedIPs'].split(','):commands.append('add_list '+peer+".allowed_ips='"+address.strip()+"'")
    with tempfile.TemporaryDirectory(prefix='.home-net-persist.',dir=NETWORK.parent) as directory:
        directory=Path(directory);(directory/'.uci').mkdir(mode=0o700)
        target=directory/'network';target.write_bytes(original);target.chmod(0o600)
        # Deleting absent options is allowed by UCI batch. No shell expansion is used.
        uci(['batch'],directory,input=('\n'.join(commands)+'\ncommit network\n').encode())
        if NETWORK.read_bytes()!=original or uci(['changes','network']).strip():raise ValueError('network changed')
        if subprocess.check_output(['awg','showconf',slot],stderr=subprocess.DEVNULL,timeout=5).rstrip(b'\n')+b'\n'!=conf:raise ValueError('runtime changed')
        # Keep the complete private baseline in the existing rollback record.
        backup=BACKUP
        if backup.is_symlink() or backup.parent.is_symlink():raise ValueError('unsafe backup')
        after=backup.with_name('network.after-persist.sha256')
        if backup.exists():
            if backup.read_bytes()!=original:
                if not after.is_symlink() and after.read_text().strip()==hashlib.sha256(original).hexdigest():return
                raise ValueError('backup differs; recovery required')
        else:
            with backup.open('xb') as stream:stream.write(original);stream.flush();os.fsync(stream.fileno())
        if after.is_symlink():raise ValueError('unsafe persistence record')
        with after.open('w') as stream:stream.write(hashlib.sha256(target.read_bytes()).hexdigest());stream.flush();os.fsync(stream.fileno())
        with target.open('rb') as stream:os.fsync(stream.fileno())
        os.replace(target,NETWORK)
        fd=os.open(NETWORK.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)

def restore_persisted():
    if not BACKUP.exists():return
    if BACKUP.is_symlink() or BACKUP.parent.is_symlink() or NETWORK.is_symlink():raise ValueError('unsafe recovery')
    current=NETWORK.read_bytes();baseline=BACKUP.read_bytes()
    if current==baseline:return
    after=BACKUP.with_name('network.after-persist.sha256')
    if after.is_symlink() or after.read_text().strip()!=hashlib.sha256(current).hexdigest():raise ValueError('network changed since persistence')
    fd,name=tempfile.mkstemp(prefix='.home-net-restore.',dir=NETWORK.parent)
    try:
        with os.fdopen(fd,'wb') as stream:stream.write(baseline);stream.flush();os.fsync(stream.fileno())
        if NETWORK.read_bytes()!=current:raise ValueError('network changed during recovery')
        os.replace(name,NETWORK)
    finally:Path(name).unlink(missing_ok=True)

FAILOVER=Path('/etc/podkop-awg-failover.conf')
WATCHER='/usr/bin/podkop-awg-failover'
ORDER_APPLIED=Path('/etc/home-net/vpn/order-applied.json')

def set_order(size):
    if size not in ('2','3') or FAILOVER.is_symlink() or not FAILOVER.is_file():raise ValueError('invalid policy')
    capabilities=subprocess.check_output([WATCHER,'--capabilities'],stderr=subprocess.DEVNULL,timeout=5).decode().split()
    if list(capabilities)!=list(SLOTS):raise ValueError('unsupported failover')
    section=Path('/etc/home-net/vpn/podkop-section').read_text().strip()
    if not re.fullmatch('[A-Za-z0-9_]+',section):raise ValueError('invalid podkop section')
    active=uci(['-q','get','podkop.'+section+'.interface']).decode().strip()
    if active not in SLOTS or size=='2' and active=='awg_backup2':raise ValueError('active reserve must remain enabled')
    if size=='3':
        hosts=[];addresses=[]
        for slot in SLOTS:
            lines=subprocess.check_output(['awg','show',slot,'endpoints'],stderr=subprocess.DEVNULL,timeout=5).decode().splitlines()
            if len(lines)!=1:raise ValueError('ambiguous peer')
            host=lines[0].split()[1].rsplit(':',1)[0];ipaddress.IPv4Address(host);hosts.append(host)
            lines=subprocess.check_output(['ip','-4','-o','address','show','dev',slot],stderr=subprocess.DEVNULL,timeout=5).decode().splitlines()
            if len(lines)!=1:raise ValueError('ambiguous address')
            address=ipaddress.IPv4Interface(lines[0].split()[3])
            if address.network.prefixlen!=32:raise ValueError('invalid address')
            addresses.append(str(address.ip))
        if len(set(hosts))!=3 or len(set(addresses))!=3:raise ValueError('duplicate reserve')
    original=FAILOVER.read_bytes()
    desired="BACKUP2_AWG='awg_backup2'" if size=='3' else "BACKUP2_AWG=''"
    lines=original.decode().splitlines();newlines=[line for line in lines if not line.startswith('BACKUP2_AWG=')]+[desired]
    replacement=('\n'.join(newlines)+'\n').encode()
    digest=hashlib.sha256(replacement).hexdigest()
    try:applied=json.loads(ORDER_APPLIED.read_text())
    except (OSError,ValueError):applied={}
    if replacement==original and applied=={'size':int(size),'digest':digest}:return
    fd,name=tempfile.mkstemp(prefix='.home-net-order.',dir=FAILOVER.parent)
    try:
        with os.fdopen(fd,'wb') as stream:stream.write(replacement);stream.flush();os.fsync(stream.fileno())
        if FAILOVER.read_bytes()!=original:raise ValueError('policy changed')
        os.replace(name,FAILOVER)
        try:
            subprocess.run(['/etc/init.d/podkop-awg-failover','restart'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=True,timeout=30)
            observed=json.loads(subprocess.check_output(['ubus','call','service','list','{"name":"podkop-awg-failover"}'],stderr=subprocess.DEVNULL,timeout=5))
            instances=observed.get('podkop-awg-failover',{}).get('instances',{})
            if not any(item.get('running') is True for item in instances.values()):raise ValueError('failover did not start')
        except (OSError,ValueError,subprocess.SubprocessError):
            fd,restore=tempfile.mkstemp(prefix='.home-net-order-restore.',dir=FAILOVER.parent)
            with os.fdopen(fd,'wb') as stream:stream.write(original);stream.flush();os.fsync(stream.fileno())
            os.replace(restore,FAILOVER)
            subprocess.run(['/etc/init.d/podkop-awg-failover','restart'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
            raise
        if ORDER_APPLIED.is_symlink() or ORDER_APPLIED.parent.is_symlink():raise ValueError('unsafe acknowledgement')
        fd,marker=tempfile.mkstemp(prefix='.home-net-order-ack.',dir=ORDER_APPLIED.parent)
        with os.fdopen(fd,'w') as stream:json.dump({'size':int(size),'digest':digest},stream);stream.flush();os.fsync(stream.fileno())
        os.replace(marker,ORDER_APPLIED)
    finally:
        Path(name).unlink(missing_ok=True)

def main():
    os.umask(0o077)
    try:
        if os.geteuid()!=0:raise ValueError('invalid invocation')
        if sys.argv[1:]==['--restore']:restore_persisted()
        elif len(sys.argv)==3 and sys.argv[1]=='--order':set_order(sys.argv[2])
        elif len(sys.argv)==3:persist(sys.argv[1],sys.argv[2])
        else:raise ValueError('invalid invocation')
    except (OSError,ValueError,subprocess.SubprocessError):
        print('HOME NET: candidate persistence requires review',file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
