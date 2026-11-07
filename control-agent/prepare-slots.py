"""Prepare disabled AWG interfaces; never reload network or select a route."""
import base64
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

NETWORK = Path('/etc/config/network')
PROTO = Path('/lib/netifd/proto/amneziawg.sh')
LOCK = Path('/var/run/home-net-vpn-maintenance.lock')
TRANSACTION = Path('/etc/home-net/vpn/transaction')
STATUS = Path('/etc/home-net/vpn/slot-preparation.json')
ROUTER_ID = Path('/etc/home-net/vpn/router-id')
SLOTS = ('awg_main', 'awg_backup')
ROLES = ('apartment-main', 'apartment-backup', 'dacha-main', 'dacha-backup')


class Blocked(Exception):
    pass


class UCI:
    def __init__(self, directory=None):
        self.prefix = ['uci']
        if directory is not None:
            saved = Path(directory) / '.uci'
            if saved.is_symlink():
                raise Blocked('unsafe_path')
            saved.mkdir(mode=0o700, exist_ok=True)
            self.prefix += ['-c', str(directory), '-t', str(saved)]

    def get(self, key):
        result = subprocess.run(self.prefix + ['-q', 'get', key], capture_output=True, timeout=5)
        return result.stdout.decode().strip() if result.returncode == 0 else None

    def dirty(self):
        return bool(subprocess.check_output(self.prefix + ['changes', 'network'], stderr=subprocess.DEVNULL, timeout=5).strip())

    def commit(self, commands):
        # Keys travel on stdin, never in command arguments or logs.
        subprocess.run(self.prefix + ['batch'], input=('\n'.join(commands) + '\ncommit network\n').encode(),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=10)


def atomic_write(path, data):
    if path.is_symlink() or path.parent.is_symlink():
        raise Blocked('unsafe_path')
    fd, temporary = tempfile.mkstemp(prefix='.slot-preparation.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        Path(temporary).unlink(missing_ok=True)


def generated_key():
    key = subprocess.check_output(['awg', 'genkey'], stderr=subprocess.DEVNULL, timeout=5).strip().decode('ascii')
    if not re.fullmatch(r'[A-Za-z0-9+/]{43}=', key) or len(base64.b64decode(key, validate=True)) != 32:
        raise Blocked('key_generation_failed')
    return key


def prepare(role=None):
    if role is not None and role not in ROLES:
        raise Blocked('invalid_role')
    if role is None:
        return {'phase': 'awaiting_role', 'slots': {}, 'changed': False, 'at': int(time.time())}
    if not PROTO.is_file():
        raise Blocked('awg_protocol_missing')
    if NETWORK.is_symlink() or not NETWORK.is_file() or NETWORK.parent.is_symlink() or LOCK.is_symlink():
        raise Blocked('unsafe_path')
    with LOCK.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Blocked('maintenance_busy') from None
        uci = UCI()
        if uci.dirty():
            raise Blocked('pending_network_changes')
        original = NETWORK.read_bytes()
        commands, inventory = [], {}
        for index, slot in enumerate(SLOTS):
            section = uci.get('network.' + slot)
            if section is not None and (section != 'interface' or uci.get('network.' + slot + '.proto') != 'amneziawg'):
                raise Blocked('slot_name_conflict')
            created = section is None
            managed = created or uci.get('network.' + slot + '.home_net_prepared') == '1'
            address = uci.get('network.' + slot + '.addresses') if not created else None
            if created:
                if subprocess.run(['ip', 'link', 'show', 'dev', slot], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=5).returncode == 0:
                    raise Blocked('slot_name_conflict')
                commands += [f'set network.{slot}=interface', f"set network.{slot}.proto='amneziawg'",
                             f"set network.{slot}.auto='0'", f"set network.{slot}.defaultroute='0'",
                             f"set network.{slot}.peerdns='0'", f"set network.{slot}.delegate='0'",
                             f"set network.{slot}.home_net_prepared='1'",
                             f"set network.{slot}.private_key='{generated_key()}'"]
            if managed and not address and role is not None:
                # Reserved role addresses are distinct across all four managed routers.
                address = f'10.8.1.{201 + 2 * ROLES.index(role) + index}/32'
                if not created:
                    running = subprocess.run(['ip', 'link', 'show', 'dev', slot],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode == 0
                    if running or uci.get('network.' + slot + '.auto') != '0' or uci.get(f'network.@amneziawg_{slot}[0]'):
                        raise Blocked('prepared_slot_in_use')
                commands.append(f"add_list network.{slot}.addresses='{address}'")
            inventory[slot] = {'state': 'prepared' if managed else 'existing', 'address': address}
        addresses = [str(ipaddress.IPv4Interface(item['address']).ip) for item in inventory.values() if item['address']]
        if len(addresses) != len(set(addresses)):
            raise Blocked('duplicate_slot_address')
        if commands:
            if TRANSACTION.exists():
                raise Blocked('transaction_open')
            runtime = subprocess.check_output(['ip', '-4', '-o', 'address', 'show'], stderr=subprocess.DEVNULL, timeout=5).decode()
            for line in runtime.splitlines():
                fields = line.split()
                if len(fields) >= 4 and fields[1].split('@')[0] not in SLOTS:
                    network = ipaddress.IPv4Interface(fields[3]).network
                    if any(ipaddress.IPv4Address(address) in network for address in addresses):
                        raise Blocked('local_address_conflict')
            with tempfile.TemporaryDirectory(prefix='.home-net-slots.', dir=NETWORK.parent) as staged:
                target = Path(staged) / 'network'
                target.write_bytes(original)
                target.chmod(0o600)
                UCI(staged).commit(commands)
                if NETWORK.read_bytes() != original or uci.dirty():
                    raise Blocked('network_changed_during_preparation')
                backup_dir = STATUS.parent / 'slot-preparation-backups'
                if backup_dir.is_symlink() or STATUS.parent.is_symlink():
                    raise Blocked('unsafe_path')
                backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
                digest = hashlib.sha256(original).hexdigest()[:16]
                backup = backup_dir / ('network-' + digest)
                if not backup.exists():
                    atomic_write(backup, original)
                atomic_write(NETWORK, target.read_bytes())
        return {'phase': 'ready' if len(addresses) == 2 else 'awaiting_role',
                'slots': inventory, 'changed': bool(commands), 'at': int(time.time())}


def main():
    os.umask(0o077)
    if os.geteuid() != 0:
        return 1
    try:
        if len(sys.argv) > 2:
            raise Blocked('invalid_role')
        role = sys.argv[1] if len(sys.argv) == 2 else None
        status = prepare(role)
    except Blocked as error:
        status = {'phase': 'blocked', 'reason': str(error), 'at': int(time.time())}
    except (OSError, ValueError, subprocess.SubprocessError):
        # Never include command output, config values or private keys in diagnostics.
        status = {'phase': 'blocked', 'reason': 'preparation_failed', 'at': int(time.time())}
    if STATUS.parent.is_symlink():
        return 1
    STATUS.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        previous = json.loads(STATUS.read_text())
    except (OSError, ValueError):
        previous = {}
    fields = lambda item: {key: value for key, value in item.items() if key not in ('at', 'changed')}
    if not isinstance(previous, dict) or fields(previous) != fields(status):
        atomic_write(STATUS, json.dumps(status).encode())
    print('HOME NET slots: ' + status['phase'])
    return 0 if status['phase'] != 'blocked' else 1


if __name__ == '__main__':
    sys.exit(main())
