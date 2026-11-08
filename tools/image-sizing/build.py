"""Public, configuration-free sizing experiment. Never upload flashable images."""
import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = json.loads(Path(__file__).with_name('sources.lock.json').read_text())
OUT = ROOT / 'sizing-results'
OUT.mkdir(exist_ok=True)
VARIANT = sys.argv[1]
assert VARIANT in ('vpn', 'panel')
WORK = ROOT / '.image-sizing-work'
WORK.mkdir(exist_ok=True)

def download(item):
    name = item.get('name', item['url'].rsplit('/', 1)[-1])
    dest = WORK / name
    print('Downloading ' + name, flush=True)
    if 'imagebuilder' in name:
        mirror = item['url'].replace('downloads.openwrt.org', 'mirror-03.infra.openwrt.org')
        with (OUT / 'download.log').open('w') as log:
            subprocess.run(['aria2c', '--max-connection-per-server=8', '--split=8',
                '--min-split-size=8M', '--max-tries=3', '--timeout=30', '--connect-timeout=15',
                '--summary-interval=30', '--file-allocation=none', '--dir=' + str(WORK),
                '--out=' + name, mirror, item['url']], stdout=log, stderr=subprocess.STDOUT,
                timeout=600, check=True)
    else:
        with urllib.request.urlopen(item['url'], timeout=60) as source, dest.open('wb') as target:
            shutil.copyfileobj(source, target)
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == item['sha256'], name
    return dest

builder = download(LOCK['imagebuilder'])
print('Extracting verified ImageBuilder', flush=True)
subprocess.run(['tar', '--zstd', '-xf', str(builder), '-C', str(WORK)], check=True)
IB = next(p for p in WORK.glob('openwrt-imagebuilder-*') if p.is_dir())
for item in LOCK['packages']:
    source = download(item)
    shutil.copy2(source, IB / 'packages' / source.name)

files = WORK / 'files'
files.mkdir(exist_ok=True)
# Include the public HOME NET runtime code so the estimate is not just a stock
# firmware image. Do not copy device files, local reports, credentials or UCI.
for name in ('scripts', 'init.d'):
    target = files / ('usr/bin' if name == 'scripts' else 'etc/init.d')
    target.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / name).iterdir():
        if source.is_file():
            shutil.copy2(source, target / source.name)
            (target / source.name).chmod(0o755)

age_sizes = {}
if VARIANT == 'panel':
    archive = download(LOCK['age'])
    with tarfile.open(archive) as source:
        for name in ('age', 'age-keygen'):
            member = source.getmember('age/' + name)
            dest = files / 'usr/bin' / name
            with source.extractfile(member) as src, dest.open('wb') as dst:
                shutil.copyfileobj(src, dst)
            dest.chmod(0o755)
            age_sizes[name] = member.size
    target = files / 'usr/sbin'
    target.mkdir(parents=True, exist_ok=True)
    for source, name in [('cudy.py', 'vpn-control-cudy.py'), ('prepare-slots.py', 'home-net-prepare-slots.py')]:
        shutil.copy2(ROOT / 'control-agent' / source, target / name)
        (target / name).chmod(0o755)

packages = ['luci', 'luci-ssl', 'sing-box', 'curl', 'jq', 'bind-dig', 'coreutils-base64',
            'tcpdump', 'owut', 'zoneinfo-europe', 'flock',
            'amneziawg-tools', 'kmod-amneziawg', 'luci-proto-amneziawg',
            'luci-i18n-amneziawg-ru', 'podkop', 'luci-app-podkop', 'luci-i18n-podkop-ru']
if VARIANT == 'panel':
    packages += ['python3-light', 'python3-openssl', 'python3-email', 'python3-urllib']
command = ['make', 'image', 'PROFILE=' + LOCK['profile'], 'PACKAGES=' + ' '.join(packages), 'FILES=' + str(files), '-j2']
(OUT / 'inputs.json').write_text(json.dumps({'variant': VARIANT, 'lock': LOCK, 'packages': packages,
    'age_binary_bytes': age_sizes, 'contains_device_configuration': False}, indent=2))
with (OUT / 'build.log').open('w') as log:
    print('Building ' + VARIANT + ' image', flush=True)
    result = subprocess.run(command, cwd=IB, stdout=log, stderr=subprocess.STDOUT, timeout=900)
if result.returncode:
    print((OUT / 'build.log').read_text()[-18000:])
    sys.exit(result.returncode)

output = IB / 'bin/targets/mediatek/filogic'
image = next(output.glob('*cudy_tr3000-v1-squashfs-sysupgrade.bin'))
with tarfile.open(image) as archive:
    kernel = next(m for m in archive.getmembers() if m.name.endswith('/kernel'))
    rootfs = next(m for m in archive.getmembers() if m.name.endswith('/root'))
    header = archive.extractfile(rootfs).read(96)
    assert header[:4] == b'hsqs', 'expected SquashFS rootfs'
    compressed_used = struct.unpack_from('<Q', header, 40)[0]

# Actual main board observed: 512 UBI PEBs; current volumes 33+50+404;
# preserve the observed 25 PEB allowance rather than treating all 128 MiB as free.
LEB = 126976
kernel_lebs = math.ceil(kernel.size / LEB)
rootfs_lebs = math.ceil(rootfs.size / LEB)
data_lebs = 512 - 25 - kernel_lebs - rootfs_lebs
data_capacity = max(data_lebs, 0) * LEB
report = {'variant': VARIANT, 'version': LOCK['openwrt'], 'profile': LOCK['profile'],
    'sizing_only_not_deployment_ready': True, 'image_bytes': image.stat().st_size,
    'kernel_bytes': kernel.size, 'rootfs_tar_bytes': rootfs.size,
    'squashfs_used_bytes': compressed_used, 'kernel_lebs': kernel_lebs,
    'rootfs_lebs': rootfs_lebs, 'estimated_data_lebs': data_lebs,
    'estimated_data_volume_bytes': data_capacity,
    'conservative_space_after_8MiB_fs_and_4MiB_operational_allowance': max(0, data_capacity - 12 * 1048576),
    'limits': ['UBIFS capacity is estimated, not measured on hardware',
               'No existing configuration or credentials included',
               'Community AWG package ABI resolved by ImageBuilder, not hardware tested',
               'No boot, VPN, panel enrollment or migration test performed',
               'Failover payload is not the pinned standalone repository; allow additional integration room']}
(OUT / 'size.json').write_text(json.dumps(report, indent=2) + '\n')
for path in output.glob('*cudy_tr3000-v1*manifest*'):
    shutil.copy2(path, OUT / path.name)
print(json.dumps(report, indent=2))
