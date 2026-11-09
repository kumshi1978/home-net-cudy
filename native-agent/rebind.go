package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func validateRebind(s object) (string, error) {
	if !exactKeys(s, "revision", "mapping", "expected", "active", "selected", "desired") {
		return "", errStopped
	}
	rev, ok := integer(s["revision"])
	if !ok || rev < 1 {
		return "", errStopped
	}
	mapping, expected, desired := obj(s["mapping"]), obj(s["expected"]), obj(s["desired"])
	kk := keys(mapping)
	if !(sameSet(kk, slots[:2]) || sameSet(kk, slots)) || !sameSet(keys(expected), kk) || !(sameSet(keys(desired), slots[:2]) || sameSet(keys(desired), slots)) {
		return "", errStopped
	}
	sources := []string{}
	for _, slot := range kk {
		source := str(mapping[slot])
		if !has(kk, source) {
			return "", errStopped
		}
		sources = append(sources, source)
	}
	if !sameSet(sources, kk) || !has(kk, str(s["active"])) || !has(kk, str(s["selected"])) {
		return "", errStopped
	}
	hosts, addresses, wanted := []string{}, []string{}, []string{}
	for _, slot := range kk {
		v := obj(expected[slot])
		port, ok := integer(v["port"])
		if !exactKeys(v, "host", "port", "address", "fingerprint") || !ip4(str(v["host"])) || !address32(str(v["address"])) || !ok || port < 1 || port > 65535 || !valid(`[a-f0-9]{64}`, str(v["fingerprint"])) {
			return "", errStopped
		}
		hosts = append(hosts, str(v["host"]))
		addresses = append(addresses, str(v["address"]))
	}
	for slot, host := range desired {
		if !has(kk, slot) || !ip4(str(host)) {
			return "", errStopped
		}
		wanted = append(wanted, str(host))
	}
	if !unique(hosts) || !unique(addresses) || !unique(wanted) {
		return "", errStopped
	}
	target := ""
	for _, slot := range kk {
		if mapping[slot] == s["selected"] {
			target = slot
		}
	}
	if desired[target] != obj(expected[str(s["selected"])])["host"] {
		return "", errStopped
	}
	return target, nil
}

var legacyNames = []string{"jc", "jmin", "jmax", "s1", "s2", "s3", "s4", "h1", "h2", "h3", "h4", "i1", "i2", "i3", "i4", "i5"}

func unquoteUCI(s string) (string, error) {
	if len(s) >= 2 && (s[0] == '\'' || s[0] == '"') && s[len(s)-1] == s[0] {
		s = s[1 : len(s)-1]
	} else if strings.ContainsAny(s, " \t") {
		return "", errStopped
	}
	if strings.ContainsAny(s, "'\"\\\n\r") {
		return "", errStopped
	}
	return s, nil
}
func networkCommands(mapping object, shown string) ([]string, error) {
	kk := keys(mapping)
	inverse := map[string]string{}
	for _, target := range kk {
		source := str(mapping[target])
		if !has(kk, source) {
			return nil, errStopped
		}
		inverse[source] = target
	}
	commands := []string{}
	lines := strings.Split(shown, "\n")
	options := map[string]string{}
	for _, line := range lines {
		p := strings.SplitN(line, "=", 2)
		if len(p) == 2 {
			options[p[0]] = p[1]
		}
	}
	for i, source := range kk {
		tmp := fmt.Sprintf("hn_rebind_%d", i)
		if _, ok := options["network."+tmp]; ok {
			return nil, errStopped
		}
		commands = append(commands, "rename network."+source+"="+tmp)
	}
	type rename struct{ section, target string }
	managed := []rename{}
	for _, line := range lines {
		p := strings.SplitN(line, "=", 2)
		if len(p) != 2 || !valid(`network\.[A-Za-z0-9_@\[\]]+`, p[0]) {
			continue
		}
		for _, source := range kk {
			if p[1] == "amneziawg_"+source {
				target := inverse[source]
				commands = append(commands, "set "+p[0]+"=amneziawg_"+target)
				if p[0] == "network.home_net_"+source {
					managed = append(managed, rename{p[0], target})
				}
			}
		}
	}
	for i, r := range managed {
		tmp := fmt.Sprintf("hn_peer_%d", i)
		if _, ok := options["network."+tmp]; ok {
			return nil, errStopped
		}
		commands = append(commands, "rename "+r.section+"="+tmp)
	}
	for i, r := range managed {
		commands = append(commands, fmt.Sprintf("rename network.hn_peer_%d=home_net_%s", i, r.target))
	}
	for i, source := range kk {
		commands = append(commands, fmt.Sprintf("rename network.hn_rebind_%d=%s", i, inverse[source]))
	}
	for _, target := range kk {
		source := str(mapping[target])
		for _, name := range legacyNames {
			alias := "network." + source + "." + name
			canonical := "network." + source + ".awg_" + name
			raw, ok := options[alias]
			if !ok {
				continue
			}
			value, e := unquoteUCI(raw)
			if e != nil {
				return nil, e
			}
			if raw, ok = options[canonical]; ok {
				v, e := unquoteUCI(raw)
				if e != nil || v != value {
					return nil, errStopped
				}
			}
			commands = append(commands, "set network."+target+".awg_"+name+"='"+value+"'", "delete network."+target+"."+name)
		}
	}
	return commands, nil
}
func (a *app) activate(changed []string) error {
	for _, cmd := range []string{"ifdown", "ifup"} {
		for _, s := range changed {
			if _, e := a.cmd(cmd, s); e != nil {
				return e
			}
		}
	}
	for _, s := range changed {
		good := false
		for attempt := 0; attempt < 20; attempt++ {
			if _, e := a.observe(s); e == nil {
				good = true
				break
			}
			a.sleep(time.Second)
		}
		if !good {
			return errStopped
		}
	}
	return nil
}
func (a *app) serve() error {
	if _, e := a.cmd(a.p("/etc/init.d/podkop"), "restart"); e != nil {
		return e
	}
	for attempt := 0; attempt < 30; attempt++ {
		if _, e := a.cmd(a.p("/usr/bin/home-net-install-verify"), "services"); e == nil {
			return nil
		}
		a.sleep(time.Second)
	}
	return errStopped
}
func (a *app) rebind(spec object) error {
	if e := safePath(a.p(vpnRoot)); e != nil {
		return e
	}
	var unlock func()
	for attempt := 0; attempt < 30; attempt++ {
		var e error
		unlock, e = lock(a.p("/var/run/home-net-vpn-maintenance.lock"))
		if e == nil {
			break
		}
		if attempt == 29 {
			return errBusy
		}
		a.sleep(time.Second)
	}
	defer unlock()
	return a.applyRebind(spec)
}
func (a *app) applyRebind(spec object) error {
	target, e := validateRebind(spec)
	if e != nil {
		return e
	}
	section, e := textFile(a.p(vpnRoot + "/podkop-section"))
	if e != nil || !valid(`[A-Za-z0-9_]+`, section) {
		return errStopped
	}
	if exists(a.p(vpnRoot+"/transaction")) || exists(a.p(vpnRoot+"/rebind-pending")) || a.dirty("network") || a.dirty("podkop") || a.get("podkop."+section+".interface") != spec["active"] {
		return errStopped
	}
	expected := obj(spec["expected"])
	mapping := obj(spec["mapping"])
	for _, s := range keys(expected) {
		v, e := a.observe(s)
		if e != nil || !equalValues(v, expected[s]) {
			return errStopped
		}
	}
	paths := []string{a.p("/etc/config/network"), a.p("/etc/config/podkop"), a.p("/etc/podkop-awg-failover.conf")}
	originals := map[string][]byte{}
	for _, p := range paths {
		b, e := read(p)
		if e != nil {
			return e
		}
		originals[p] = b
	}
	shown, e := a.text("uci", "-q", "-X", "show", "network")
	if e != nil {
		return e
	}
	commands, e := networkCommands(mapping, shown)
	if e != nil {
		return e
	}
	network, e := a.edited(paths[0], commands)
	if e != nil {
		return e
	}
	podkop, e := a.edited(paths[1], []string{"set podkop." + section + ".interface='" + target + "'"})
	if e != nil {
		return e
	}
	aligned := true
	desired := obj(spec["desired"])
	for s, h := range desired {
		if obj(expected[str(mapping[s])])["host"] != h {
			aligned = false
		}
	}
	order := []string{}
	if !aligned {
		order = append(order, target)
	}
	for _, s := range slots {
		if desired[s] != nil && (aligned || s != target) {
			order = append(order, s)
		}
	}
	replacements := map[string][]byte{paths[0]: network, paths[1]: podkop, paths[2]: orderedPolicy(originals[paths[2]], order)}
	backup, e := os.MkdirTemp(a.p(vpnRoot), "rebind-")
	if e != nil {
		return e
	}
	for _, p := range paths {
		if e = exclusive(filepath.Join(backup, filepath.Base(p)), originals[p]); e != nil {
			return e
		}
	}
	if e = save(filepath.Join(backup, "request.json"), spec); e != nil {
		return e
	}
	pending := a.p(vpnRoot + "/rebind-pending")
	if e = atomic(pending, []byte(filepath.Base(backup))); e != nil {
		return e
	}
	changed := []string{}
	for _, s := range keys(mapping) {
		source := str(mapping[s])
		different := s != source
		for _, name := range legacyNames {
			if strings.Contains("\n"+shown, "\nnetwork."+source+"."+name+"=") {
				different = true
			}
		}
		if different {
			changed = append(changed, s)
		}
	}
	perform := func() error {
		for _, p := range paths {
			current, e := read(p)
			if e != nil || !bytes.Equal(current, originals[p]) {
				return errStopped
			}
		}
		for _, p := range paths {
			if e = atomic(p, replacements[p]); e != nil {
				return e
			}
		}
		if len(changed) > 0 {
			if e = a.activate(changed); e != nil {
				return e
			}
		}
		for _, s := range keys(mapping) {
			v, e := a.observe(s)
			if e != nil || !equalValues(v, expected[str(mapping[s])]) {
				return errStopped
			}
		}
		if has(changed, str(spec["active"])) || target != spec["active"] {
			if e = a.serve(); e != nil {
				return e
			}
		} else if _, e = a.cmd(a.p("/usr/bin/home-net-install-verify"), "services"); e != nil {
			return e
		}
		for _, s := range keys(mapping) {
			good := false
			for _, url := range []string{"https://ifconfig.me/ip", "https://api.ipify.org"} {
				b, e := a.cmd("curl", "-q", "-4", "--noproxy", "*", "--interface", "if!"+s, "--connect-timeout", "5", "--max-time", "10", "--max-filesize", "128", "-fsS", url)
				if e == nil && strings.TrimSpace(string(b)) == obj(expected[str(mapping[s])])["host"] {
					good = true
					break
				}
			}
			if !good {
				return errStopped
			}
		}
		if _, e = a.cmd(a.p("/etc/init.d/podkop-awg-failover"), "restart"); e != nil {
			return e
		}
		if e = atomic(filepath.Join(backup, "phase"), []byte("applied\n")); e != nil {
			return e
		}
		return os.Remove(pending)
	}
	if e = perform(); e == nil {
		return nil
	}
	for _, p := range paths {
		current, re := read(p)
		if re != nil || (!bytes.Equal(current, originals[p]) && !bytes.Equal(current, replacements[p])) {
			atomic(filepath.Join(backup, "phase"), []byte("recovery_required\n"))
			return errStopped
		}
	}
	for _, p := range paths {
		if atomic(p, originals[p]) != nil {
			return errStopped
		}
	}
	if len(changed) > 0 {
		if a.activate(changed) != nil {
			return errStopped
		}
	}
	if a.serve() != nil {
		return errStopped
	}
	if _, e = a.cmd(a.p("/etc/init.d/podkop-awg-failover"), "restart"); e != nil {
		return e
	}
	for _, s := range keys(expected) {
		v, e := a.observe(s)
		if e != nil || !equalValues(v, expected[s]) {
			return errStopped
		}
	}
	if atomic(filepath.Join(backup, "phase"), []byte("rolled-back\n")) != nil {
		return errStopped
	}
	if os.Remove(pending) != nil {
		return errStopped
	}
	return errStopped
}
