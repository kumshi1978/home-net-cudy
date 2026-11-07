import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
import fcntl
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('slots', Path(__file__).resolve().parents[1] / 'control-agent/prepare-slots.py')
slots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(slots)


class FakeUCI:
    pending = False

    def __init__(self, directory=None):
        self.file = Path(directory) / 'network' if directory else slots.NETWORK

    def get(self, key):
        return json.loads(self.file.read_text()).get(key)

    def dirty(self):
        return self.pending

    def commit(self, commands):
        values = json.loads(self.file.read_text())
        for command in commands:
            operation, option = shlex.split(command)
            key, value = option.split('=', 1)
            if operation == 'add_list' and key in values:
                raise AssertionError('unexpected list replacement')
            values[key] = value
        self.file.write_text(json.dumps(values))


@unittest.skipUnless(hasattr(os, 'O_DIRECTORY'), 'requires Linux directory fsync')
class SlotPreparation(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.network = self.root / 'network'
        self.network.write_text(json.dumps({'network.lan': 'interface', 'network.lan.proto': 'static',
                                           'network.lan.ipaddr': '192.168.1.1'}))
        proto = self.root / 'amneziawg.sh'
        proto.touch()
        for name, value in {'NETWORK': self.network, 'PROTO': proto, 'LOCK': self.root / 'lock',
                            'TRANSACTION': self.root / 'transaction', 'STATUS': self.root / 'vpn/status.json'}.items():
            patcher = patch.object(slots, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(slots, 'UCI', FakeUCI)
        patcher.start()
        self.addCleanup(patcher.stop)
        FakeUCI.pending = False
        self.runtime = b'2: br-lan inet 192.168.1.1/24 scope global br-lan\n'
        def output(command, **options):
            if command == ['awg', 'genkey']:
                return b'A' * 43 + b'=\n'
            self.assertEqual(command, ['ip', '-4', '-o', 'address', 'show'])
            return self.runtime
        patcher = patch.object(slots.subprocess, 'check_output', side_effect=output)
        self.output = patcher.start()
        self.addCleanup(patcher.stop)
        patcher = patch.object(slots.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_new_slots_disabled_and_addresses_assigned_after_approval(self):
        before = self.network.read_bytes()
        result = slots.prepare()
        self.assertEqual(result['phase'], 'awaiting_role')
        self.assertFalse(result['changed'])
        self.assertEqual(self.network.read_bytes(), before)
        self.output.assert_not_called()
        self.assertFalse((slots.STATUS.parent / 'slot-preparation-backups').exists())
        result = slots.prepare('dacha-main')
        self.assertEqual([item['address'] for item in result['slots'].values()], ['10.8.1.205/32', '10.8.1.206/32'])
        prepared = self.network.read_bytes()
        self.assertFalse(slots.prepare('dacha-main')['changed'])
        self.assertEqual(self.network.read_bytes(), prepared)
        self.assertEqual(sum(call.args[0] == ['awg', 'genkey'] for call in self.output.call_args_list), 2)

    def test_existing_slots_and_open_transaction_remain_unchanged(self):
        values = json.loads(self.network.read_text())
        for index, slot in enumerate(slots.SLOTS):
            values.update({f'network.{slot}': 'interface', f'network.{slot}.proto': 'amneziawg',
                           f'network.{slot}.addresses': f'10.8.1.{index+3}/32', f'network.{slot}.private_key': 'existing'})
        self.network.write_text(json.dumps(values))
        slots.TRANSACTION.mkdir()
        before = self.network.read_bytes()
        self.assertFalse(slots.prepare('apartment-backup')['changed'])
        self.assertEqual(self.network.read_bytes(), before)
        self.output.assert_not_called()

    def test_conflicts_and_incomplete_transaction_fail_without_writes(self):
        before = self.network.read_bytes()
        FakeUCI.pending = True
        with self.assertRaisesRegex(slots.Blocked, 'pending_network_changes'):
            slots.prepare('apartment-main')
        FakeUCI.pending = False
        self.runtime = b'2: br-lan inet 10.8.1.1/24 scope global br-lan\n'
        with self.assertRaisesRegex(slots.Blocked, 'local_address_conflict'):
            slots.prepare('apartment-main')
        self.runtime = b''
        slots.TRANSACTION.mkdir()
        with self.assertRaisesRegex(slots.Blocked, 'transaction_open'):
            slots.prepare('apartment-main')
        self.assertEqual(self.network.read_bytes(), before)

    def test_slot_name_collision_does_not_replace_an_existing_interface(self):
        self.network.write_text(json.dumps({'network.awg_main': 'interface', 'network.awg_main.proto': 'wireguard'}))
        before = self.network.read_bytes()
        with self.assertRaisesRegex(slots.Blocked, 'slot_name_conflict'):
            slots.prepare('apartment-main')
        self.assertEqual(self.network.read_bytes(), before)

    def test_role_address_ranges_are_disjoint(self):
        addresses = set()
        for role in slots.ROLES:
            self.network.write_text('{}')
            result = slots.prepare(role)
            for detail in result['slots'].values():
                self.assertNotIn(detail['address'], addresses)
                addresses.add(detail['address'])
        self.assertEqual(len(addresses), 8)

    def test_shared_maintenance_lock_blocks_preparation(self):
        before = self.network.read_bytes()
        with slots.LOCK.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(slots.Blocked, 'maintenance_busy'):
                slots.prepare('apartment-main')
        self.assertEqual(self.network.read_bytes(), before)
