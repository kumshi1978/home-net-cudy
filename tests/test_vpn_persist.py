import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('persist',Path(__file__).resolve().parents[1]/'scripts/home-net-vpn-persist.py')
persist=importlib.util.module_from_spec(spec);spec.loader.exec_module(persist)
key=base64.b64encode(b'a'*32).decode()
CONF=('[Interface]\nPrivateKey = '+key+'\nJc = 4\n[Peer]\nPublicKey = '+key+'\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = 192.0.2.3:4340\n').encode()

class Persist(unittest.TestCase):
    def test_parser_rejects_injection_multiple_peers_and_invalid_addresses(self):
        self.assertEqual(persist.parse(CONF)['Jc'],'4')
        for bad in (CONF+b'[Peer]\n',CONF.replace(b'Jc = 4',b"Jc = '4'"),CONF.replace(b'192.0.2.3',b'999.0.0.1'),CONF.replace(b'PrivateKey',b'PostUp'),CONF.replace(b'0.0.0.0/0',b'not-a-network')):
            with self.assertRaises(ValueError):persist.parse(bad)

    @unittest.skipUnless(hasattr(os,'O_DIRECTORY'),'Linux fsync required')
    def test_atomic_persistence_preserves_unrelated_network_and_private_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);network=root/'network';backup=root/'backup';backup.mkdir()
            original=b'private baseline with unrelated LAN and other VPN\n';network.write_bytes(original)
            calls=[]
            def uci(args,directory=None,input=None):
                calls.append((args,directory,input))
                if args==['changes','network']:return b''
                if args==['-q','get','network.awg_backup2.proto']:return b'amneziawg'
                if args==['-q','show','network']:return b"network.lan=interface\nnetwork.awg_main=interface\nnetwork.awg_backup2=interface\nnetwork.awg_backup2.private_key='old'\n"
                self.assertEqual(args,['batch'])
                text=input.decode();self.assertNotIn('delete network.lan',text);self.assertNotIn('set network.awg_main',text)
                self.assertIn("set network.awg_backup2.auto='1'",text)
                self.assertIn("endpoint_host='192.0.2.3'",text)
                (Path(directory)/'network').write_bytes(original+b'candidate persisted\n');return b''
            with patch.object(persist,'NETWORK',network),patch.object(persist,'BACKUP',backup/'baseline'),patch.object(persist,'uci',side_effect=uci),patch.object(persist.subprocess,'check_output',return_value=CONF):
                with self.assertRaises(ValueError):persist.persist('awg_backup2','0'*64)
                self.assertEqual(network.read_bytes(),original)
                persist.persist('awg_backup2',hashlib.sha256(CONF).hexdigest())
                candidate=network.read_bytes()
                persist.persist('awg_backup2',hashlib.sha256(CONF).hexdigest())
                self.assertEqual(network.read_bytes(),candidate)
                persist.restore_persisted()
                self.assertEqual(network.read_bytes(),original)
                # Restore refuses to erase an unrelated edit after a completed persistence.
                network.write_bytes(candidate+b'unrelated edit')
                with self.assertRaises(ValueError):persist.restore_persisted()
                self.assertEqual(network.read_bytes(),candidate+b'unrelated edit')
                network.write_bytes(candidate)
            self.assertEqual((backup/'baseline').read_bytes(),original)
            self.assertEqual(network.read_bytes(),original+b'candidate persisted\n')

    def test_pending_uci_changes_never_write(self):
        with tempfile.TemporaryDirectory() as directory:
            network=Path(directory)/'network';network.write_bytes(b'unchanged')
            with patch.object(persist,'NETWORK',network),patch.object(persist,'uci',return_value=b'pending'),patch.object(persist.subprocess,'check_output') as command:
                with self.assertRaises(ValueError):persist.persist('awg_backup2','a'*64)
                command.assert_not_called()
            self.assertEqual(network.read_bytes(),b'unchanged')
