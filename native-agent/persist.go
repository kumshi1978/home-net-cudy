package main

import (
	"bytes"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var interfaceFields = map[string]string{"PrivateKey": "private_key", "ListenPort": "listen_port", "Jc": "awg_jc", "Jmin": "awg_jmin", "Jmax": "awg_jmax", "S1": "awg_s1", "S2": "awg_s2", "S3": "awg_s3", "S4": "awg_s4", "H1": "awg_h1", "H2": "awg_h2", "H3": "awg_h3", "H4": "awg_h4", "I1": "awg_i1", "I2": "awg_i2", "I3": "awg_i3", "I4": "awg_i4", "I5": "awg_i5"}
var peerFields = map[string]string{"PublicKey": "public_key", "PresharedKey": "preshared_key", "PersistentKeepalive": "persistent_keepalive", "AdvancedSecurity": "advanced_security"}

func parseAWG(conf []byte) (map[string]string, error) {
	for _, b := range conf {
		if b > 127 {
			return nil, errStopped
		}
	}
	values := map[string]string{}
	sections := []string{}
	section := ""
	for _, raw := range strings.Split(string(conf), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "[Interface]" || line == "[Peer]" {
			sections = append(sections, line)
			section = line
			continue
		}
		pair := strings.SplitN(line, "=", 2)
		if len(pair) != 2 || section == "" {
			return nil, errStopped
		}
		name, value := strings.TrimSpace(pair[0]), strings.TrimSpace(pair[1])
		if _, ok := values[name]; ok || value == "" || strings.ContainsAny(value, "'\"\n\r") {
			return nil, errStopped
		}
		if section == "[Interface]" {
			if _, ok := interfaceFields[name]; !ok {
				return nil, errStopped
			}
		} else {
			if _, ok := peerFields[name]; !ok && name != "Endpoint" && name != "AllowedIPs" {
				return nil, errStopped
			}
		}
		values[name] = value
	}
	if !sameOrdered(sections, []string{"[Interface]", "[Peer]"}) {
		return nil, errStopped
	}
	for _, k := range []string{"PrivateKey", "PublicKey", "Endpoint", "AllowedIPs"} {
		if values[k] == "" {
			return nil, errStopped
		}
	}
	for _, k := range []string{"PrivateKey", "PublicKey", "PresharedKey"} {
		if v, ok := values[k]; ok && !key32(v) {
			return nil, errStopped
		}
	}
	h, p, e := net.SplitHostPort(values["Endpoint"])
	n, ne := strconv.Atoi(p)
	if e != nil || !ip4(h) || ne != nil || !valid(`[0-9]+`, p) || n < 1 || n > 65535 {
		return nil, errStopped
	}
	for _, s := range strings.Split(values["AllowedIPs"], ",") {
		s = strings.TrimSpace(s)
		if _, e := netip.ParsePrefix(s); e != nil {
			if _, e = netip.ParseAddr(s); e != nil {
				return nil, errStopped
			}
		}
	}
	for k, v := range values {
		if has([]string{"I1", "I2", "I3", "I4", "I5"}, k) {
			if len(v) < 1 || len(v) > 2048 || !valid(`[A-Za-z0-9<>:_.,=+ /-]+`, v) {
				return nil, errStopped
			}
		} else if !has([]string{"PrivateKey", "PublicKey", "PresharedKey", "Endpoint", "AllowedIPs", "AdvancedSecurity"}, k) && !valid(`[0-9]+`, v) {
			return nil, errStopped
		}
	}
	return values, nil
}
func normalizeConf(b []byte) []byte { return append(bytes.TrimRight(b, "\n"), '\n') }
func sortedStringKeys(m map[string]string) []string {
	o := object{}
	for k, v := range m {
		o[k] = v
	}
	return keys(o)
}
func persistenceCommands(slot string, values map[string]string, shown string) ([]string, error) {
	lines := strings.Split(shown, "\n")
	commands := []string{}
	peers := []string{}
	options := map[string]bool{}
	for _, line := range lines {
		p := strings.SplitN(line, "=", 2)
		if len(p) == 2 {
			options[p[0]] = true
			if p[1] == "amneziawg_"+slot {
				if !valid(`network\.[A-Za-z0-9_@\[\]]+`, p[0]) {
					return nil, errStopped
				}
				peers = append(peers, p[0])
			}
		}
	}
	for i := len(peers) - 1; i >= 0; i-- {
		commands = append(commands, "delete "+peers[i])
	}
	for _, name := range sortedStringKeys(interfaceFields) {
		option := interfaceFields[name]
		if v, ok := values[name]; ok {
			commands = append(commands, "set network."+slot+"."+option+"='"+v+"'")
		} else if options["network."+slot+"."+option] {
			commands = append(commands, "delete network."+slot+"."+option)
		}
	}
	peer := "network.home_net_" + slot
	for _, line := range lines {
		if strings.HasPrefix(line, peer+"=") && line != peer+"=amneziawg_"+slot {
			return nil, errStopped
		}
	}
	commands = append(commands, "set "+peer+"=amneziawg_"+slot, "set network."+slot+".auto='1'", "set "+peer+".route_allowed_ips='0'")
	for _, name := range sortedStringKeys(peerFields) {
		if v, ok := values[name]; ok {
			commands = append(commands, "set "+peer+"."+peerFields[name]+"='"+v+"'")
		}
	}
	host, port, _ := net.SplitHostPort(values["Endpoint"])
	commands = append(commands, "set "+peer+".endpoint_host='"+host+"'", "set "+peer+".endpoint_port='"+port+"'")
	for _, ip := range strings.Split(values["AllowedIPs"], ",") {
		commands = append(commands, "add_list "+peer+".allowed_ips='"+strings.TrimSpace(ip)+"'")
	}
	return commands, nil
}
func (a *app) persist(slot, expected string) error {
	if !has(slots, slot) || !valid(`[a-f0-9]{64}`, expected) || a.dirty("network") || a.get("network."+slot+".proto") != "amneziawg" {
		return errStopped
	}
	network := a.p("/etc/config/network")
	original, e := read(network)
	if e != nil {
		return e
	}
	raw, e := a.cmd("awg", "showconf", slot)
	if e != nil {
		return e
	}
	conf := normalizeConf(raw)
	if hash(conf) != expected {
		return errStopped
	}
	values, e := parseAWG(conf)
	if e != nil {
		return e
	}
	shown, e := a.text("uci", "-q", "show", "network")
	if e != nil {
		return e
	}
	commands, e := persistenceCommands(slot, values, shown)
	if e != nil {
		return e
	}
	replacement, e := a.edited(network, commands)
	if e != nil {
		return e
	}
	current, e := read(network)
	if e != nil || !bytes.Equal(current, original) || a.dirty("network") {
		return errStopped
	}
	again, e := a.cmd("awg", "showconf", slot)
	if e != nil || !bytes.Equal(normalizeConf(again), conf) {
		return errStopped
	}
	backup := a.p(vpnRoot + "/transaction/backup/network.before-persist")
	after := filepath.Join(filepath.Dir(backup), "network.after-persist.sha256")
	if exists(backup) {
		baseline, e := read(backup)
		if e != nil {
			return e
		}
		if !bytes.Equal(baseline, original) {
			digest, e := textFile(after)
			if e == nil && digest == hash(original) {
				return nil
			}
			return errStopped
		}
	} else if e = exclusive(backup, original); e != nil {
		return e
	}
	if e = atomic(after, []byte(hash(replacement))); e != nil {
		return e
	}
	return atomic(network, replacement)
}
func (a *app) restorePersisted() error {
	backup := a.p(vpnRoot + "/transaction/backup/network.before-persist")
	if !exists(backup) {
		return nil
	}
	baseline, e := read(backup)
	if e != nil {
		return e
	}
	network := a.p("/etc/config/network")
	current, e := read(network)
	if e != nil {
		return e
	}
	if bytes.Equal(current, baseline) {
		return nil
	}
	after, e := textFile(filepath.Join(filepath.Dir(backup), "network.after-persist.sha256"))
	if e != nil || after != hash(current) {
		return errStopped
	}
	again, e := read(network)
	if e != nil || !bytes.Equal(again, current) {
		return errStopped
	}
	return atomic(network, baseline)
}
func orderedPolicy(original []byte, order []string) []byte {
	out := []string{}
	for _, line := range strings.Split(strings.TrimSuffix(string(original), "\n"), "\n") {
		if !strings.HasPrefix(line, "MAIN_AWG=") && !strings.HasPrefix(line, "BACKUP_AWG=") && !strings.HasPrefix(line, "BACKUP2_AWG=") {
			out = append(out, line)
		}
	}
	for i, key := range []string{"MAIN_AWG", "BACKUP_AWG", "BACKUP2_AWG"} {
		v := ""
		if i < len(order) {
			v = order[i]
		}
		out = append(out, key+"='"+v+"'")
	}
	return []byte(strings.Join(out, "\n") + "\n")
}
func (a *app) setOrder(value string) error {
	order := strings.Split(value, ",")
	if (len(order) != 2 && len(order) != 3) || !unique(order) {
		return errStopped
	}
	for _, s := range order {
		if !has(slots, s) {
			return errStopped
		}
	}
	watcher := a.p("/usr/bin/podkop-awg-failover")
	b, e := read(watcher)
	if e != nil || !bytes.Contains(prefix512(b), []byte(`if [ "${1:-}" = --capabilities ]; then`)) {
		return errStopped
	}
	caps, e := a.text(watcher, "--capabilities")
	if e != nil || !sameOrdered(strings.Fields(caps), slots) {
		return errStopped
	}
	section, e := textFile(a.p(vpnRoot + "/podkop-section"))
	if e != nil || !valid(`[A-Za-z0-9_]+`, section) || !has(order, a.get("podkop."+section+".interface")) {
		return errStopped
	}
	hosts, addresses := []string{}, []string{}
	for _, s := range order {
		v, e := a.observe(s)
		if e != nil {
			return e
		}
		hosts = append(hosts, str(v["host"]))
		addresses = append(addresses, str(v["address"]))
	}
	if !unique(hosts) || !unique(addresses) {
		return errStopped
	}
	path := a.p("/etc/podkop-awg-failover.conf")
	original, e := read(path)
	if e != nil {
		return e
	}
	replacement := orderedPolicy(original, order)
	ack := object{"size": len(order), "order": order, "digest": hash(replacement)}
	if old, e := load(a.p(vpnRoot + "/order-applied.json")); e == nil && bytes.Equal(replacement, original) && equalValues(old, ack) {
		return nil
	}
	if e = atomic(path, replacement); e != nil {
		return e
	}
	_, e = a.cmd(a.p("/etc/init.d/podkop-awg-failover"), "restart")
	if e == nil {
		var data []byte
		data, e = a.cmd("ubus", "call", "service", "list", `{"name":"podkop-awg-failover"}`)
		if e == nil {
			var status object
			status, e = decode(data)
			running := false
			if e == nil {
				for _, item := range obj(obj(status["podkop-awg-failover"])["instances"]) {
					if obj(item)["running"] == true {
						running = true
					}
				}
			}
			if !running {
				e = errStopped
			}
		}
	}
	if e != nil {
		current, readErr := read(path)
		if readErr != nil || !bytes.Equal(current, replacement) {
			return errStopped
		}
		if atomic(path, original) != nil {
			return errStopped
		}
		a.run(30*time.Second, nil, a.p("/etc/init.d/podkop-awg-failover"), "restart")
		return errStopped
	}
	return save(a.p(vpnRoot+"/order-applied.json"), ack)
}

var _ = os.ErrNotExist
