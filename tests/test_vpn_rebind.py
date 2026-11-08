import copy, importlib.util, json, tempfile, unittest
from pathlib import Path
from unittest.mock import patch

loader=importlib.util.spec_from_file_location('rebind',Path(__file__).parents[1]/'scripts/home-net-vpn-rebind.py')
m=importlib.util.module_from_spec(loader);loader.loader.exec_module(m)

def fixture():
    slots=m.SLOTS
    return dict(revision=2,mapping={slots[0]:slots[1],slots[1]:slots[0],slots[2]:slots[2]},
                active=slots[1],selected=slots[1],desired={slots[0]:'192.0.2.2',slots[1]:'192.0.2.1',slots[2]:'192.0.2.3'},
                expected={slot:dict(host='192.0.2.'+str(i+1),port=4340,address='10.8.1.'+str(i+1)+'/32',fingerprint=str(i)*64) for i,slot in enumerate(slots)})

class Rebind(unittest.TestCase):
    def test_permutation_preserves_endpoint_identity_and_rejects_duplicates(self):
        spec=fixture();self.assertEqual(m.validate(spec),'awg_main')
        for edit in (lambda s:s['mapping'].update(awg_backup='awg_backup'),
                     lambda s:s['mapping'].update(lan='lan'),
                     lambda s:s['expected']['awg_backup'].update(address='10.8.1.1/32'),
                     lambda s:s.update(selected='lan'),
                     lambda s:s.update(revision=0)):
            bad=copy.deepcopy(spec);edit(bad)
            with self.assertRaises((ValueError,KeyError)):m.validate(bad)

    def test_cycles_rotate_interface_and_managed_peer_names(self):
        spec=fixture();text='network.awg_main=interface\nnetwork.awg_backup=interface\nnetwork.home_net_awg_main=amneziawg_awg_main\nnetwork.home_net_awg_backup=amneziawg_awg_backup\n'
        commands=m.network_commands(spec['mapping'],text)
        self.assertIn('set network.home_net_awg_main=amneziawg_awg_backup',commands)
        self.assertIn('rename network.hn_peer_0=home_net_awg_backup',commands)
        self.assertIn('rename network.hn_rebind_1=awg_main',commands)
        with self.assertRaises(ValueError):m.network_commands(spec['mapping'],text+'network.hn_rebind_0=interface\n')

    def run_case(self,fail=False,stale=False):
        spec=fixture()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);network=root/'network';podkop=root/'podkop';failover=root/'failover';(root/'podkop-section').write_text('main')
            originals={network:b'network original',podkop:b'podkop original',failover:b"MAIN_AWG='awg_backup'\nBACKUP_AWG='awg_main'\nBACKUP2_AWG='awg_backup2'\n"}
            for p,v in originals.items():p.write_bytes(v)
            def observe(slot):
                source=spec['mapping'][slot] if network.read_bytes()==b'network changed' else slot
                value=dict(spec['expected'][source])
                if stale:value['port']=1234
                return value
            def command(*args,**kwargs):
                if args[:2]==('uci','changes'):return b''
                if args[:3]==('uci','-q','get'):return b'awg_backup'
                if args[:4]==('uci','-q','-X','show'):return b'network.awg_main=interface\nnetwork.awg_backup=interface\n'
                if args[0]=='curl':return b'192.0.2.99' if fail else b'192.0.2.2'
                return b''
            with patch.multiple(m,ROOT=root,NETWORK=network,PODKOP=podkop,FAILOVER=failover),patch.object(m,'command',side_effect=command),patch.object(m,'observe',side_effect=observe),patch.object(m,'edited',side_effect=lambda path,cmd:(path.name+' changed').encode()),patch.object(m,'activate') as activate,patch.object(m,'serve'):
                if fail or stale:
                    with self.assertRaises(ValueError):m.apply(spec)
                    for p,v in originals.items():self.assertEqual(p.read_bytes(),v)
                    if stale:activate.assert_not_called()
                    else:self.assertEqual(activate.call_count,2)
                else:
                    m.apply(spec)
                    self.assertEqual(network.read_bytes(),b'network changed')
                    self.assertIn(b"MAIN_AWG='awg_main'",failover.read_bytes())
                    self.assertEqual(activate.call_args.args[0],['awg_main','awg_backup'])
                self.assertFalse((root/'rebind-pending').exists())
    def test_success(self):self.run_case()
    def test_probe_failure_restores_configs_and_interfaces(self):self.run_case(fail=True)
    def test_changed_snapshot_rejected_before_mutation(self):self.run_case(stale=True)

if __name__=='__main__':unittest.main()
