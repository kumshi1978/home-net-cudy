import base64
import fcntl
import hashlib
import hmac
import http.client
import ipaddress
import json
import os
import re
import signal
import socket
import ssl
import subprocess
import sys
import time
import tempfile
from pathlib import Path
from threading import Event

HOST = "ui-control.kumshi.ru"
CONFIG = Path("/etc/vpn-control-agent.json")
IDENTITY = Path("/etc/home-net/keys/age-identity.txt")
STATE = Path("/etc/home-net/vpn/control-agent")
TRANSACTION = STATE.parent / "transaction"
HELPER = "/usr/bin/home-net-vpn-router"
SLOT_PREPARER = Path("/usr/sbin/home-net-prepare-slots.py")
TERMINAL = {"verified", "failed", "recovery_required", "expired"}
VERIFY_DELAYS = (0, 10, 20, 30, 40, 50)
POLL_INTERVAL = 60
POLL_ERRORS = (OSError, ValueError, KeyError, TypeError, http.client.HTTPException, subprocess.SubprocessError)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


class WANConnection(http.client.HTTPSConnection):
    def __init__(self, ip, device):
        super().__init__(HOST, timeout=15, context=ssl.create_default_context())
        self.ip = str(ipaddress.IPv4Address(ip))
        self.device = device

    def connect(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as raw:
            raw.settimeout(self.timeout)
            raw.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, self.device.encode() + b"\0")
            raw.connect((self.ip, 443))
            self.sock = self._context.wrap_socket(raw, server_hostname=HOST)


def call(config, action, body):
    conn = WANConnection(config["server_ip"], config["wan_device"])
    try:
        path = "/agent/register" if action == "register" else "/agent/" + config.get("device_id", config.get("router", "")) + "/" + action
        headers = {"Content-Type": "application/json"}
        if action != "register":
            headers["Authorization"] = "Bearer " + config["token"]
        conn.request("POST", path,
                     canonical(body), headers)
        response = conn.getresponse()
        data = response.read(100001)
        if response.status not in (200, 201) or len(data) > 100000:
            raise ValueError("control server rejected request")
        return json.loads(data)
    finally:
        conn.close()


def save_config(config):
    if CONFIG.is_symlink():
        raise ValueError("unsafe agent config")
    fd, name = tempfile.mkstemp(prefix=".vpn-control-agent.", dir=CONFIG.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(config, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, CONFIG)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def register():
    if not IDENTITY.is_file() or IDENTITY.is_symlink():
        raise ValueError("router-local encryption identity is unavailable")
    recipient = subprocess.check_output(["age-keygen", "-y", str(IDENTITY)], text=True, timeout=5).strip()
    if not re.fullmatch(r"age1[ac-hj-np-z02-9]{58}", recipient):
        raise ValueError("invalid public recipient")
    wan = json.loads(subprocess.check_output(["ubus", "call", "network.interface.wan", "status"], text=True, timeout=5))
    device = wan.get("l3_device") or wan.get("device")
    if not isinstance(device, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,15}", device):
        raise ValueError("physical WAN unavailable")
    config = {"server_ip": "188.120.247.74", "wan_device": device}
    response = call(config, "register", {"recipient": recipient, "name": socket.gethostname()[:64]})
    envelope = base64.b64decode(response["envelope"], validate=True)
    if len(envelope) > 65536:
        raise ValueError("invalid enrollment envelope")
    credentials = json.loads(subprocess.check_output(["age", "-d", "-i", str(IDENTITY)], input=envelope, timeout=10))
    expected = "device-" + hashlib.sha256(recipient.encode()).hexdigest()[:24]
    if (credentials.get("device_id") != expected or not re.fullmatch(r"[0-9a-f]{64}", credentials.get("token", ""))
            or not re.fullmatch(r"[0-9a-f]{64}", credentials.get("signing_key", ""))):
        raise ValueError("invalid enrollment credentials")
    config.update(credentials)
    save_config(config)
    return config


def verify(config, response):
    job = response["job"]
    expected = hmac.digest(bytes.fromhex(config["signing_key"]), canonical(job), "sha256").hex()
    if not hmac.compare_digest(expected, response["signature"]):
        raise ValueError("invalid job signature")
    if (job["router"] != config["router"] or
            not re.fullmatch("[0-9a-f]{32}", job["id"]) or
            not re.fullmatch("[A-Z]{2}", job["country"]) or
            type(job["expires"]) is not int):
        raise ValueError("invalid job metadata")
    if "target" in job or "address" in job:
        if job.get("target") not in {"awg_main", "awg_backup", "awg_backup2"}:
            raise ValueError("invalid target slot")
        if ipaddress.IPv4Interface(job.get("address", "")).network.prefixlen != 32:
            raise ValueError("invalid target address")
    if job.get('kind') not in (None,'accept_verified'):raise ValueError('unknown job kind')
    if job.get('kind')=='accept_verified':
        if not re.fullmatch('[0-9a-f]{32}',job.get('transaction_id','')):raise ValueError('invalid transaction id')
        if response['payload']!='' or job['digest']!=hashlib.sha256(b'').hexdigest():raise ValueError('invalid control payload')
        return job,b''
    payload = base64.b64decode(response["payload"], validate=True)
    if (len(payload) > 65536 or not payload.startswith(b"age-encryption.org/v1\n") or
            not hmac.compare_digest(hashlib.sha256(payload).hexdigest(), job["digest"])):
        raise ValueError("invalid encrypted payload")
    return job, payload


def save_receipt(path, status):
    temp = path.with_suffix(".tmp")
    with temp.open("w") as stream:
        stream.write(status + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    temp.replace(path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def helper(action, *arguments, payload=None):
    return subprocess.run([HELPER, action, *arguments], input=payload,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def execute(job, payload, receipt):
    if job.get('kind')=='accept_verified':
        identifier=job['transaction_id'];completed=TRANSACTION.parent/'completed'/identifier
        try:
            if (completed/'phase').read_text().strip()=='accepted':return 'verified'
        except OSError:pass
        if job['expires']<=time.time():return 'expired'
        try:
            if (TRANSACTION/'deployment-id').read_text().strip()!=identifier:return 'recovery_required'
        except OSError:return 'recovery_required'
        return 'verified' if helper('accept-id',identifier) else 'recovery_required'
    if receipt.exists():
        previous = receipt.read_text().strip()
        if previous == "started" and job.get("commit") is True:
            completed = TRANSACTION.parent / "completed" / job["id"]
            try:
                if (not completed.is_symlink() and (completed / "phase").read_text().strip() == "accepted"
                        and (completed / "payload.sha256").read_text().strip() == job["digest"]):
                    return "verified"
            except OSError:
                pass
            try:
                if ((TRANSACTION/'phase').read_text().strip()=='accepted' and (TRANSACTION/'deployment-id').read_text().strip()==job['id']
                        and (TRANSACTION/'payload.sha256').read_text().strip()==job['digest']):
                    return 'verified' if helper('accept-id',job['id']) else 'recovery_required'
            except OSError:pass
        return previous if previous in TERMINAL else "recovery_required"
    if job["expires"] <= time.time():
        return "expired"
    if TRANSACTION.exists():
        return "recovery_required"
    save_receipt(receipt, "started")
    action = "prepare-upload"
    arguments = [job["id"], job["country"]]
    if "target" in job:
        action = "prepare-upload-target"
        arguments.extend((job["target"], job["address"]))
    if not helper(action, *arguments, payload=payload):
        if not TRANSACTION.exists():
            return "failed"
        return "recovery_required"
    deployment = TRANSACTION / "deployment-id"
    for delay in VERIFY_DELAYS:
        if delay:
            time.sleep(delay)
        if not deployment.is_file() or deployment.read_text().strip() != job["id"]:
            return "recovery_required"
        if helper("verify") and deployment.is_file() and deployment.read_text().strip() == job["id"]:
            if job.get("commit") is not True or helper("accept"):
                return "verified"
            return "recovery_required"
    # The existing rollback can change active policy after an independent failover.
    # Only the operator may authorize rollback or promotion in that case.
    return "recovery_required"


def router_topology():
    def read(*command):
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL, timeout=3).strip()

    slots = {}
    active = None
    try:
        section = (STATE.parent / "podkop-section").read_text().strip()
        if re.fullmatch(r"[A-Za-z0-9_]+", section):
            active = read("uci", "-q", "get", f"podkop.{section}.interface")
    except (OSError, subprocess.SubprocessError):
        pass
    for slot in ("awg_main", "awg_backup", "awg_backup2"):
        try:
            _, endpoint = read("awg", "show", slot, "endpoints").split()
            host, port = endpoint.rsplit(":", 1)
            addresses = [line.split()[3] for line in read("ip", "-4", "-o", "address", "show", "dev", slot).splitlines()]
            address, = addresses
            public_key = read("awg", "show", slot, "public-key")
            handshake = int(read("awg", "show", slot, "latest-handshakes").split()[1])
            slots[slot] = {"host": str(ipaddress.IPv4Address(host)), "port": int(port),
                           "address": str(ipaddress.IPv4Interface(address)),
                           "fingerprint": hashlib.sha256(public_key.encode()).hexdigest(),
                           "verified":0 < handshake <= time.time() and time.time() - handshake <= 180}
        except (OSError, ValueError, IndexError, subprocess.SubprocessError):
            continue
    transaction = None
    transaction_id = None
    try:
        status = read(HELPER, "status")
        match = re.search(r"^TRANSACTION_STATE='([a-z-]+)'$", status, re.MULTILINE)
        if match:
            transaction = match[1]
    except (OSError, subprocess.SubprocessError):
        pass
    ready = (Path(HELPER).is_file() and (STATE.parent / "adapter").is_file()
             and (STATE.parent / "podkop-section").is_file())
    try:
        candidate=(TRANSACTION/'deployment-id').read_text().strip()
        if re.fullmatch('[0-9a-f]{32}',candidate):transaction_id=candidate
    except OSError:pass
    result = {"active": active if active in slots else None, "slots": slots, "transaction": transaction,
              "delivery_ready": ready}
    if transaction_id:result["transaction_id"]=transaction_id
    try:
        result["preparation"] = json.loads((STATE.parent / "slot-preparation.json").read_text())
    except (OSError, ValueError):
        pass
    result['failover_slots']=[]
    try:
        watcher=Path('/usr/bin/podkop-awg-failover')
        with watcher.open() as stream:prefix=stream.read(512)
        if 'if [ "${1:-}" = --capabilities ]; then' in prefix:
            result['failover_slots']=read(str(watcher),'--capabilities').split()
    except (OSError,ValueError,subprocess.SubprocessError):pass
    result["order_size"] = 0
    try:
        acknowledgement = json.loads((STATE.parent / "order-applied.json").read_text())
        digest = hashlib.sha256(Path("/etc/podkop-awg-failover.conf").read_bytes()).hexdigest()
        if acknowledgement.get("digest") == digest and acknowledgement.get("size") in (2,3):
            result["order_size"] = acknowledgement["size"]
            result["order"] = acknowledgement.get("order",[])
    except (OSError,ValueError):
        pass
    result["prepared_revision"] = json.loads(CONFIG.read_text()).get("prepared_revision", 0) if CONFIG.exists() else 0
    try:
        capabilities = read(HELPER, "capabilities")
        result["controller_slots"] = [slot for slot in capabilities.split() if slot in ("awg_main", "awg_backup", "awg_backup2")]
    except (OSError, ValueError, subprocess.SubprocessError):
        result["controller_slots"] = ["awg_main", "awg_backup"]
    return result


def prepare_slots(role=None, backup2=False):
    if SLOT_PREPARER.is_file():
        command = [sys.executable, str(SLOT_PREPARER)]
        if role:
            command.append(role)
            if backup2:
                command.append("--backup2")
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=False)


def verify_plan(config,response):
    plan = response.get("plan")
    if plan is None:return None
    if not isinstance(plan, dict) or not hmac.compare_digest(
            response.get("plan_signature", ""), hmac.digest(bytes.fromhex(config["signing_key"]), canonical(plan), "sha256").hex()):
        raise ValueError("invalid slot plan signature")
    if (type(plan.get("revision")) is not int or plan["revision"] < config.get("prepared_revision", 0)
            or type(plan.get("expires")) is not int or not time.time() < plan["expires"] <= time.time() + 1860
            or plan.get("slots") not in (["awg_main","awg_backup"], ["awg_main","awg_backup","awg_backup2"])
            or ('order_size' in plan)!=('order' in plan)
            or 'order' in plan and (not isinstance(plan['order'],list) or len(plan['order']) not in (2,3)
                or len(set(plan['order']))!=len(plan['order']) or not set(plan['order'])<=set(plan['slots'])
                or type(plan['order_size']) is not int or plan['order_size']!=len(plan['order']))):
        raise ValueError("invalid slot plan")
    return plan


def poll_once():
    os.umask(0o077)
    config = json.loads(CONFIG.read_text()) if CONFIG.exists() else register()
    roles = {"apartment-main", "apartment-backup", "dacha-main", "dacha-backup"}
    if config.get("router") is not None and config["router"] not in roles:
        raise ValueError("router is outside the canary scope")
    if config.get("router") and (STATE.parent / "router-id").read_text().strip() != config["router"]:
        raise ValueError("configured router does not match the local identity")
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,15}", config["wan_device"]):
        raise ValueError("invalid WAN device")
    STATE.mkdir(mode=0o700, exist_ok=True)
    with (STATE / "poll.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        response = call(config, "poll", {"topology": router_topology()})
        if config.get("device_id") and response.get("assignment"):
            assignment = response["assignment"]
            if assignment not in roles or config.get("router") not in (None, assignment):
                raise ValueError("unexpected router assignment")
            local_id = STATE.parent / "router-id"
            if local_id.is_symlink() or (local_id.exists() and local_id.read_text().strip() != assignment):
                raise ValueError("local router assignment conflicts with panel")
            if not local_id.exists():
                with local_id.open("x") as stream:
                    stream.write(assignment + "\n")
            if config.get("router") != assignment:
                config["router"] = assignment
                save_config(config)
        plan = verify_plan(config,response)
        backup2 = bool(plan and "awg_backup2" in plan["slots"])
        role = config.get("router") if response.get("prepare_slots") is True else None
        if backup2 and role:prepare_slots(role, backup2=True)
        else:prepare_slots(role)
        if plan and role:
            status = json.loads((STATE.parent / "slot-preparation.json").read_text())
            if status.get("phase") == "ready" and set(status.get("slots", {})) == set(plan["slots"]):
                if config.get("prepared_revision") != plan["revision"]:
                    config["prepared_revision"] = plan["revision"]; save_config(config)
        if plan and plan.get("order_size") in (2,3):
            if not helper("set-order", ",".join(plan["order"])):
                raise ValueError("ordered failover is not ready")
        if response["job"] is None:
            return
        if not config.get("router") or not Path(HELPER).is_file():
            raise ValueError("HOME NET router helper is unavailable or not assigned")
        job, payload = verify(config, response)
        receipt = STATE / job["id"]
        result = "expired" if plan and job.get("commit") is True and job.get("revision") != plan["revision"] else execute(job, payload, receipt)
        save_receipt(receipt, result)
        call(config, "result", {"id": job["id"], "status": result})


def poll_safely():
    try:
        poll_once()
    except POLL_ERRORS as error:
        print("VPN Control poll failed: " + type(error).__name__, file=sys.stderr)
        return 1
    return 0


def poll_loop(stop):
    while not stop.is_set():
        poll_safely()
        stop.wait(POLL_INTERVAL)


if __name__ == "__main__":
    if sys.argv[1:] == ["--loop"]:
        stopped = Event()
        signal.signal(signal.SIGTERM, lambda *_: stopped.set())
        signal.signal(signal.SIGINT, lambda *_: stopped.set())
        poll_loop(stopped)
    elif len(sys.argv) == 1:
        sys.exit(poll_safely())
    else:
        sys.exit("usage: vpn-control-cudy.py [--loop]")
