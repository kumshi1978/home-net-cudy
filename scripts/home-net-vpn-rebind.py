#!/usr/bin/python3
"""Apply a signed, snapshot-bound slot permutation; never accept shell commands."""
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

SLOTS = ('awg_main', 'awg_backup', 'awg_backup2')
ROOT = Path('/etc/home-net/vpn')
NETWORK = Path('/etc/config/network')
PODKOP = Path('/etc/config/podkop')
FAILOVER = Path('/etc/podkop-awg-failover.conf')
LOCK = Path('/var/run/home-net-vpn-maintenance.lock')

def command(*args, input=None):
    return subprocess.check_output(args, input=input, stderr=subprocess.DEVNULL, timeout=60)

def observe(slot):
    hostport = command('awg','show',slot,'endpoints').decode().split()
    if len(hostport) != 2: raise ValueError('ambiguous peer')
    host, port = hostport[1].rsplit(':',1)
    address = command('ip','-4','-o','address','show','dev',slot).decode().splitlines()
    if len(address) != 1: raise ValueError('ambiguous address')
    return dict(host=str(ipaddress.IPv4Address(host)), port=int(port),
                address=str(ipaddress.IPv4Interface(address[0].split()[3])),
                fingerprint=hashlib.sha256(command('awg','show',slot,'public-key').decode().strip().encode()).hexdigest())

def validate(spec):
    if set(spec) != {'revision','mapping','expected','active','selected','desired'}: raise ValueError('invalid fields')
    mapping=spec['mapping']; expected=spec['expected']
    if type(spec['revision']) is not int or spec['revision'] < 1: raise ValueError('invalid revision')
    if not isinstance(mapping,dict) or set(mapping) not in (set(SLOTS[:2]),set(SLOTS)) or set(mapping.values()) != set(mapping): raise ValueError('invalid permutation')
    if set(expected) != set(mapping) or spec['active'] not in mapping or spec['selected'] not in mapping: raise ValueError('invalid snapshot')
    if set(spec['desired']) not in (set(SLOTS[:2]),set(SLOTS)) or not set(spec['desired']) <= set(mapping): raise ValueError('invalid desired slots')
    for value in expected.values():
        if set(value) != {'host','port','address','fingerprint'}: raise ValueError('invalid snapshot fields')
        ipaddress.IPv4Address(value['host']); address=ipaddress.IPv4Interface(value['address'])
        if address.network.prefixlen != 32 or type(value['port']) is not int or not 1 <= value['port'] <= 65535 or not re.fullmatch('[a-f0-9]{64}',value['fingerprint']): raise ValueError('invalid snapshot value')
    for host in spec['desired'].values(): ipaddress.IPv4Address(host)
    for field in ('host','address'):
        if len({value[field] for value in expected.values()}) != len(expected): raise ValueError('duplicate snapshot')
    if len(set(spec['desired'].values())) != len(spec['desired']): raise ValueError('duplicate desired server')
    target=next(slot for slot,source in mapping.items() if source == spec['selected'])
    if spec['desired'].get(target) != expected[spec['selected']]['host']: raise ValueError('selected server is not desired')
    return target

def network_commands(mapping, shown):
    """Rename interfaces via temporary names; rotate managed peer names too."""
    inverse={source:target for target,source in mapping.items()}
    lines=shown.splitlines(); result=[]
    for index, source in enumerate(mapping):
        if any(line.startswith('network.hn_rebind_'+str(index)+'=') for line in lines): raise ValueError('temporary section collision')
        result.append('rename network.'+source+'=hn_rebind_'+str(index))
    managed=[]
    for line in lines:
        match=re.fullmatch(r'(network\.[A-Za-z0-9_@\[\]]+)=(amneziawg_)(awg_main|awg_backup|awg_backup2)',line)
        if match and match[3] in inverse:
            result.append('set '+match[1]+'=amneziawg_'+inverse[match[3]])
            if match[1] == 'network.home_net_'+match[3]: managed.append((match[1],inverse[match[3]]))
    for index,(name,target) in enumerate(managed):
        if any(line.startswith('network.hn_peer_'+str(index)+'=') for line in lines): raise ValueError('temporary peer collision')
        result.append('rename '+name+'=hn_peer_'+str(index))
    for index,(name,target) in enumerate(managed): result.append('rename network.hn_peer_'+str(index)+'=home_net_'+target)
    for index,source in enumerate(mapping): result.append('rename network.hn_rebind_'+str(index)+'='+inverse[source])
    return result

def atomic(path, content):
    if path.is_symlink() or path.parent.is_symlink(): raise ValueError('unsafe path')
    fd,name=tempfile.mkstemp(prefix='.home-net-rebind.',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as stream: stream.write(content); stream.flush(); os.fsync(stream.fileno())
        os.replace(name,path)
    finally: Path(name).unlink(missing_ok=True)

def edited(config, commands):
    with tempfile.TemporaryDirectory(prefix='home-net-rebind-') as tmp:
        directory=Path(tmp); (directory/'.uci').mkdir(); (directory/config.name).write_bytes(config.read_bytes())
        command('uci','-c',tmp,'-t',tmp+'/.uci','batch',input=('\n'.join(commands)+'\ncommit '+config.name+'\n').encode())
        return (directory/config.name).read_bytes()

def activate(slots):
    for slot in slots: command('ifdown',slot)
    for slot in slots: command('ifup',slot)
    for slot in slots:
        for attempt in range(20):
            try: observe(slot); break
            except (ValueError,OSError,subprocess.SubprocessError):
                if attempt == 19: raise
                time.sleep(1)

def serve():
    command('/etc/init.d/podkop','restart')
    for attempt in range(30):
        try: command('home-net-install-verify','services'); return
        except (OSError,subprocess.SubprocessError):
            if attempt == 29: raise
            time.sleep(1)

def apply(spec):
    target=validate(spec)
    section=(ROOT/'podkop-section').read_text().strip()
    if not re.fullmatch('[A-Za-z0-9_]+',section): raise ValueError('invalid local section')
    if (ROOT/'transaction').exists() or (ROOT/'rebind-pending').exists(): raise ValueError('operation pending')
    if command('uci','changes','network').strip() or command('uci','changes','podkop').strip(): raise ValueError('uncommitted configuration')
    if command('uci','-q','get','podkop.'+section+'.interface').decode().strip() != spec['active']: raise ValueError('active slot changed')
    for slot,value in spec['expected'].items():
        if observe(slot) != value: raise ValueError('router snapshot changed')
    shown=command('uci','-q','-X','show','network').decode()
    network=edited(NETWORK,network_commands(spec['mapping'],shown))
    podkop=edited(PODKOP,["set podkop."+section+".interface='"+target+"'"])
    # Keep the selected known-good server first during replacement of an active profile.
    aligned=all(spec['expected'][spec['mapping'][slot]]['host']==host for slot,host in spec['desired'].items())
    order=[slot for slot in SLOTS if slot in spec['desired']] if aligned else [target]+[slot for slot in SLOTS if slot in spec['desired'] and slot != target]
    failover=FAILOVER.read_text().splitlines()
    failover=[line for line in failover if not line.startswith(('MAIN_AWG=','BACKUP_AWG=','BACKUP2_AWG='))]
    failover += [key+"='"+value+"'" for key,value in zip(('MAIN_AWG','BACKUP_AWG','BACKUP2_AWG'),order+['']*(3-len(order)))]
    originals={path:path.read_bytes() for path in (NETWORK,PODKOP,FAILOVER)}
    backup=Path(tempfile.mkdtemp(prefix='rebind-',dir=ROOT))
    for path,content in originals.items(): (backup/path.name).write_bytes(content)
    (backup/'request.json').write_text(json.dumps(spec))
    atomic(ROOT/'rebind-pending',backup.name.encode())
    changed=[slot for slot,source in spec['mapping'].items() if slot != source]
    try:
        for path,content in originals.items():
            if path.read_bytes() != content: raise ValueError('configuration changed')
        atomic(NETWORK,network); atomic(PODKOP,podkop); atomic(FAILOVER,('\n'.join(failover)+'\n').encode())
        if changed: activate(changed)
        for slot,source in spec['mapping'].items():
            if observe(slot) != spec['expected'][source]: raise ValueError('post-apply profile mismatch')
        serve()
        exit_ip=command('curl','-q','-4','--noproxy','*','--interface','if!'+target,'--connect-timeout','5','--max-time','15','--max-filesize','128','-fsS','https://ifconfig.me/ip').decode().strip()
        if exit_ip != spec['expected'][spec['selected']]['host']: raise ValueError('selected tunnel probe failed')
        command('/etc/init.d/podkop-awg-failover','restart')
        (backup/'phase').write_text('applied\n')
        (ROOT/'rebind-pending').unlink()
    except (ValueError,OSError,subprocess.SubprocessError):
        for path,content in originals.items(): atomic(path,content)
        if changed: activate(changed)
        serve(); command('/etc/init.d/podkop-awg-failover','restart')
        for slot,value in spec['expected'].items():
            if observe(slot) != value: raise ValueError('rollback requires recovery')
        (backup/'phase').write_text('rolled-back\n'); (ROOT/'rebind-pending').unlink()
        raise

def main():
    import sys
    os.umask(0o077)
    try:
        if os.geteuid()!=0 or len(sys.argv)!=2 or len(sys.argv[1])>8192: raise ValueError('invalid invocation')
        if LOCK.is_symlink() or ROOT.is_symlink(): raise ValueError('unsafe lock')
        for path in (NETWORK,PODKOP,FAILOVER):
            if path.is_symlink() or path.parent.is_symlink(): raise ValueError('unsafe configuration')
        with LOCK.open('a') as lock:
            for attempt in range(30):
                try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); break
                except BlockingIOError:
                    if attempt == 29: return 75
                    time.sleep(1)
            apply(json.loads(sys.argv[1]))
    except (ValueError,KeyError,TypeError,OSError,subprocess.SubprocessError):
        print('HOME NET: slot rebinding stopped; inspect local recovery record',file=sys.stderr); return 1
    return 0

if __name__=='__main__': raise SystemExit(main())
