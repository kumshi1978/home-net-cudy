package main

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func (a *app) observe(slot string) (object, error) {
	if !has(slots, slot) {
		return nil, errStopped
	}
	ept, e := a.text("awg", "show", slot, "endpoints")
	if e != nil {
		return nil, e
	}
	fields := strings.Fields(ept)
	if len(fields) != 2 {
		return nil, errStopped
	}
	host, port, e := net.SplitHostPort(fields[1])
	if e != nil || !ip4(host) {
		return nil, errStopped
	}
	pn, e := strconv.ParseInt(port, 10, 64)
	if e != nil || pn < 1 || pn > 65535 {
		return nil, errStopped
	}
	out, e := a.text("ip", "-4", "-o", "address", "show", "dev", slot)
	if e != nil || strings.Contains(out, "\n") {
		return nil, errStopped
	}
	ff := strings.Fields(out)
	if len(ff) < 4 || !address32(ff[3]) {
		return nil, errStopped
	}
	pub, e := a.text("awg", "show", slot, "public-key")
	if e != nil {
		return nil, e
	}
	return object{"host": host, "port": pn, "address": ff[3], "fingerprint": hash([]byte(pub))}, nil
}
func (a *app) uci(directory string, input []byte, args ...string) ([]byte, error) {
	prefix := []string{}
	if directory != "" {
		prefix = []string{"-c", directory, "-t", filepath.Join(directory, ".uci")}
	}
	return a.run(10*time.Second, input, "uci", append(prefix, args...)...)
}
func (a *app) get(key string) string {
	b, e := a.uci("", nil, "-q", "get", key)
	if e != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}
func (a *app) dirty(name string) bool {
	b, e := a.uci("", nil, "changes", name)
	return e != nil || len(bytes.TrimSpace(b)) != 0
}
func (a *app) edited(path string, commands []string) ([]byte, error) {
	if e := safePath(path); e != nil {
		return nil, e
	}
	original, e := read(path)
	if e != nil {
		return nil, e
	}
	tmp, e := os.MkdirTemp(filepath.Dir(path), ".home-net-uci.")
	if e != nil {
		return nil, e
	}
	defer os.RemoveAll(tmp)
	if e = mkdir(filepath.Join(tmp, ".uci")); e != nil {
		return nil, e
	}
	target := filepath.Join(tmp, filepath.Base(path))
	if e = os.WriteFile(target, original, 0600); e != nil {
		return nil, e
	}
	batch := []byte(strings.Join(commands, "\n") + "\ncommit " + filepath.Base(path) + "\n")
	if _, e = a.uci(tmp, batch, "batch"); e != nil {
		return nil, e
	}
	return read(target)
}
func key32(s string) bool {
	b, e := base64.StdEncoding.Strict().DecodeString(s)
	return e == nil && len(b) == 32 && base64.StdEncoding.EncodeToString(b) == s
}
func (a *app) prepareSlots(role string, backup2 bool) (object, error) {
	now := a.now().Unix()
	status := object{"phase": "awaiting_role", "slots": object{}, "changed": false, "at": now}
	path := a.p(vpnRoot + "/slot-preparation.json")
	if e := mkdir(a.p(vpnRoot)); e != nil {
		return nil, e
	}
	finish := func(s object) (object, error) {
		prev, e := load(path)
		if e == nil {
			pc := object{}
			sc := object{}
			for k, v := range prev {
				if k != "at" && k != "changed" {
					pc[k] = v
				}
			}
			for k, v := range s {
				if k != "at" && k != "changed" {
					sc[k] = v
				}
			}
			if equalValues(pc, sc) {
				return s, nil
			}
		}
		return s, save(path, s)
	}
	if role == "" {
		return finish(status)
	}
	if !has(roles, role) {
		return nil, errStopped
	}
	if !exists(a.p("/lib/netifd/proto/amneziawg.sh")) {
		return nil, errStopped
	}
	network := a.p("/etc/config/network")
	if e := safePath(network); e != nil {
		return nil, e
	}
	unlock, e := lock(a.p("/var/run/home-net-vpn-maintenance.lock"))
	if e != nil {
		return finish(object{"phase": "blocked", "reason": "maintenance_busy", "at": now})
	}
	defer unlock()
	if a.dirty("network") {
		return finish(object{"phase": "blocked", "reason": "pending_network_changes", "at": now})
	}
	original, e := read(network)
	if e != nil {
		return nil, e
	}
	wanted := slots[:2]
	if backup2 {
		wanted = slots
	}
	inventory := object{}
	commands := []string{}
	addresses := []netip.Addr{}
	roleIndex := 0
	for i, v := range roles {
		if v == role {
			roleIndex = i
		}
	}
	for index, slot := range wanted {
		kind := a.get("network." + slot)
		created := kind == ""
		if !created && (kind != "interface" || a.get("network."+slot+".proto") != "amneziawg") {
			return nil, errStopped
		}
		managed := created || a.get("network."+slot+".home_net_prepared") == "1"
		address := a.get("network." + slot + ".addresses")
		if created {
			if _, e = a.cmd("ip", "link", "show", "dev", slot); e == nil {
				return nil, errStopped
			}
			b, e := a.cmd("awg", "genkey")
			key := strings.TrimSpace(string(b))
			if e != nil || !key32(key) {
				return nil, errStopped
			}
			commands = append(commands, "set network."+slot+"=interface", "set network."+slot+".proto='amneziawg'", "set network."+slot+".auto='0'", "set network."+slot+".defaultroute='0'", "set network."+slot+".peerdns='0'", "set network."+slot+".delegate='0'", "set network."+slot+".home_net_prepared='1'", "set network."+slot+".private_key='"+key+"'")
		}
		if managed && address == "" {
			n := 201 + 2*roleIndex + index
			if slot == "awg_backup2" {
				n = 209 + roleIndex
			}
			address = fmt.Sprintf("10.8.1.%d/32", n)
			if !created {
				_, running := a.cmd("ip", "link", "show", "dev", slot)
				if running == nil || a.get("network."+slot+".auto") != "0" || a.get("network.@amneziawg_"+slot+"[0]") != "" {
					return nil, errStopped
				}
			}
			commands = append(commands, "add_list network."+slot+".addresses='"+address+"'")
		}
		state := "existing"
		if managed {
			state = "prepared"
		}
		var addr any
		if address != "" {
			if !address32(address) {
				return nil, errStopped
			}
			p, _ := netip.ParsePrefix(address)
			for _, old := range addresses {
				if old == p.Addr() {
					return nil, errStopped
				}
			}
			addresses = append(addresses, p.Addr())
			addr = address
		}
		inventory[slot] = object{"state": state, "address": addr}
	}
	if len(commands) > 0 {
		if exists(a.p(vpnRoot + "/transaction")) {
			return nil, errStopped
		}
		runtime, e := a.text("ip", "-4", "-o", "address", "show")
		if e != nil {
			return nil, e
		}
		for _, line := range strings.Split(runtime, "\n") {
			f := strings.Fields(line)
			if len(f) < 4 {
				continue
			}
			dev := strings.Split(f[1], "@")[0]
			if has(wanted, dev) {
				continue
			}
			p, e := netip.ParsePrefix(f[3])
			if e != nil {
				return nil, errStopped
			}
			for _, address := range addresses {
				if p.Contains(address) {
					return nil, errStopped
				}
			}
		}
		staged, e := a.edited(network, commands)
		if e != nil {
			return nil, e
		}
		current, e := read(network)
		if e != nil || !bytes.Equal(current, original) || a.dirty("network") {
			return nil, errStopped
		}
		dir := a.p(vpnRoot + "/slot-preparation-backups")
		if e = mkdir(dir); e != nil {
			return nil, e
		}
		backup := filepath.Join(dir, "network-"+hash(original)[:16])
		if !exists(backup) {
			if e = exclusive(backup, original); e != nil {
				return nil, e
			}
		}
		if e = atomic(network, staged); e != nil {
			return nil, e
		}
	}
	phase := "awaiting_role"
	if len(addresses) == len(wanted) {
		phase = "ready"
	}
	return finish(object{"phase": phase, "slots": inventory, "changed": len(commands) > 0, "at": now})
}
