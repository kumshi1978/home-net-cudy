#!/usr/bin/python3
"""Persist only a verified inactive AWG slot. Invoked under the controller lock."""
import base64
import hashlib
import ipaddress
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
        if backup.exists():
            if backup.read_bytes()!=original:raise ValueError('backup differs; recovery required')
        else:
            with backup.open('xb') as stream:stream.write(original);stream.flush();os.fsync(stream.fileno())
        with target.open('rb') as stream:os.fsync(stream.fileno())
        os.replace(target,NETWORK)
        fd=os.open(NETWORK.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)

def main():
    os.umask(0o077)
    try:
        if os.geteuid()!=0 or len(sys.argv)!=3:raise ValueError('invalid invocation')
        persist(sys.argv[1],sys.argv[2])
    except (OSError,ValueError,subprocess.SubprocessError):
        print('HOME NET: candidate persistence requires review',file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
