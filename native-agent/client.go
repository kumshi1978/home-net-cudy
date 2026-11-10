package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const host = "ui-control.kumshi.ru"
const configPath = "/etc/vpn-control-agent.json"
const vpnRoot = "/etc/home-net/vpn"
const statePath = vpnRoot + "/control-agent"
const helperPath = "/usr/bin/home-net-vpn-router"

func ip4(s string) bool { ip, e := netip.ParseAddr(s); return e == nil && ip.Is4() && ip.String() == s }
func address32(s string) bool {
	p, e := netip.ParsePrefix(s)
	return e == nil && p.Addr().Is4() && p.Bits() == 32 && p.String() == s
}
func signature(config object, v any, sig string) bool {
	k, e := hex.DecodeString(str(config["signing_key"]))
	if e != nil || len(k) != 32 || !valid(`[a-f0-9]{64}`, sig) {
		return false
	}
	b, e := canonical(v)
	if e != nil {
		return false
	}
	h := hmac.New(sha256.New, k)
	h.Write(b)
	want, _ := hex.DecodeString(sig)
	return hmac.Equal(h.Sum(nil), want)
}
func bearerToken(s string)bool{if len(s)<32||len(s)>512{return false};for _,r:=range s{if r<=32||r>=127{return false}};return true}
func (a *app) call(config object, action string, body any) (object, error) {
	ip := str(config["server_ip"])
	device := str(config["wan_device"])
	if !ip4(ip) || !valid(`[A-Za-z0-9_.-]{1,15}`, device) {
		return nil, errStopped
	}
	id := str(config["device_id"])
	if id == "" {
		id = str(config["router"])
	}
	path := "/agent/register"
	if action != "register" {
		if !valid(`[a-z0-9-]{1,80}`, id) || !has([]string{"poll", "result"}, action) || !bearerToken(str(config["token"])) {
			return nil, errStopped
		}
		path = "/agent/" + id + "/" + action
	}
	b, e := canonical(body)
	if e != nil {
		return nil, e
	}
	dialer := net.Dialer{Timeout: 15 * time.Second, Control: bindDevice(device)}
	tr := &http.Transport{Proxy: nil, TLSClientConfig: &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}, DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		if address != host+":443" {
			return nil, errStopped
		}
		return dialer.DialContext(ctx, "tcp4", net.JoinHostPort(ip, "443"))
	}, TLSHandshakeTimeout: 15 * time.Second, DisableKeepAlives: true, MaxResponseHeaderBytes: 16384}
	defer tr.CloseIdleConnections()
	client := &http.Client{Transport: tr, Timeout: 15 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, e := http.NewRequest("POST", "https://"+host+path, bytes.NewReader(b))
	if e != nil {
		return nil, errStopped
	}
	req.Header.Set("Content-Type", "application/json")
	if action != "register" {
		req.Header.Set("Authorization", "Bearer "+str(config["token"]))
	}
	res, e := client.Do(req)
	if e != nil {
		return nil, errStopped
	}
	defer res.Body.Close()
	if res.StatusCode != 200 && res.StatusCode != 201 {
		return nil, errStopped
	}
	data, e := io.ReadAll(io.LimitReader(res.Body, 100001))
	if e != nil || len(data) > 100000 {
		return nil, errStopped
	}
	return decode(data)
}
func (a *app) register() (object, error) {
	identity, e := a.identity()
	if e != nil {
		return nil, e
	}
	recipient := identity.Recipient().String()
	out, e := a.cmd("ubus", "call", "network.interface.wan", "status")
	if e != nil {
		return nil, e
	}
	wan, e := decode(out)
	if e != nil {
		return nil, e
	}
	device := str(wan["l3_device"])
	if device == "" {
		device = str(wan["device"])
	}
	if !valid(`[A-Za-z0-9_.-]{1,15}`, device) {
		return nil, errStopped
	}
	config := object{"server_ip": "188.120.247.74", "wan_device": device}
	name, _ := os.Hostname()
	if len([]rune(name)) > 64 {
		name = string([]rune(name)[:64])
	}
	response, e := a.call(config, "register", object{"recipient": recipient, "name": name})
	if e != nil {
		return nil, e
	}
	encrypted, e := base64.StdEncoding.Strict().DecodeString(str(response["envelope"]))
	if e != nil || base64.StdEncoding.EncodeToString(encrypted)!=str(response["envelope"]) {
		return nil, errStopped
	}
	clear, e := a.decrypt(encrypted)
	if e != nil {
		return nil, e
	}
	creds, e := decode(clear)
	if e != nil || !exactKeys(creds,"device_id","token","signing_key") || str(creds["device_id"]) != "device-"+hash([]byte(recipient))[:24] || !valid(`[a-f0-9]{64}`, str(creds["token"])) || !valid(`[a-f0-9]{64}`, str(creds["signing_key"])) {
		return nil, errStopped
	}
	for k, v := range creds {
		config[k] = v
	}
	if e = save(a.p(configPath), config); e != nil {
		return nil, e
	}
	return config, nil
}
func verifyJob(config, response object) (object, []byte, error) {
	job := obj(response["job"])
	if job == nil || !signature(config, job, str(response["signature"])) || job["router"] != config["router"] || !valid(`[a-f0-9]{32}`, str(job["id"])) || !valid(`[A-Z]{2}`, str(job["country"])) {
		return nil, nil, errStopped
	}
	if _, ok := integer(job["expires"]); !ok {
		return nil, nil, errStopped
	}
	_, target := job["target"]
	_, address := job["address"]
	if target || address {
		if !has(slots, str(job["target"])) || !address32(str(job["address"])) {
			return nil, nil, errStopped
		}
	}
	kind := str(job["kind"])
	if job["kind"] != nil && kind != "accept_verified" {
		return nil, nil, errStopped
	}
	if kind == "accept_verified" {
		if !valid(`[a-f0-9]{32}`, str(job["transaction_id"])) || response["payload"] != "" || job["digest"] != hash(nil) {
			return nil, nil, errStopped
		}
		return job, nil, nil
	}
	payload, e := base64.StdEncoding.Strict().DecodeString(str(response["payload"]))
	if e != nil || base64.StdEncoding.EncodeToString(payload)!=str(response["payload"]) || len(payload) > 65536 || !bytes.HasPrefix(payload, []byte("age-encryption.org/v1\n")) || job["digest"] != hash(payload) {
		return nil, nil, errStopped
	}
	return job, payload, nil
}
func verifyPlan(config, response object, now int64) (object, error) {
	if response["plan"] == nil {
		return nil, nil
	}
	p := obj(response["plan"])
	if p == nil || !signature(config, p, str(response["plan_signature"])) {
		return nil, errStopped
	}
	rev, ok := integer(p["revision"])
	previous, _ := integer(config["prepared_revision"])
	if received,valid := integer(config["received_revision"]); valid && received > previous { previous=received }
	expires, good := integer(p["expires"])
	ss, validSlots := stringsOf(p["slots"])
	if !ok || rev < previous || !good || expires <= now || expires > now+1860 || !validSlots || !(sameOrdered(ss, slots[:2]) || sameOrdered(ss, slots)) {
		return nil, errStopped
	}
	_, osize := p["order_size"]
	_, order := p["order"]
	if osize != order {
		return nil, errStopped
	}
	if order {
		v, ok := stringsOf(p["order"])
		n, good := integer(p["order_size"])
		if !ok || !good || n != int64(len(v)) || (n != 2 && n != 3) || !unique(v) {
			return nil, errStopped
		}
		for _, s := range v {
			if !has(ss, s) {
				return nil, errStopped
			}
		}
	}
	if raw, ok := p["rebind"]; ok {
		r := obj(raw)
		if r == nil || r["revision"] != p["revision"] {
			return nil, errStopped
		}
		if _, e := validateRebind(r); e != nil {
			return nil, e
		}
	}
	if raw,ok := p["remove_backup2"]; ok {
		order,validOrder:=stringsOf(p["order"])
		if raw!=true || !validOrder || !sameOrdered(order,slots[:2]) || p["rebind"]!=nil || p["expected"]==nil { return nil,errStopped }
	}
	if raw,present:=p["expected"];present {
		expected:=obj(raw);order,ok:=stringsOf(p["order"])
		if !ok || !sameSet(keys(expected),order) { return nil,errStopped }
		for _,slot:=range order {
			v:=obj(expected[slot]);port,good:=integer(v["port"])
			if !exactKeys(v,"host","port","address","fingerprint") || !ip4(str(v["host"])) || !address32(str(v["address"])) || !good || port<1 || port>65535 || !valid(`[a-f0-9]{64}`,str(v["fingerprint"])) {return nil,errStopped}
		}
	}
	return p, nil
}
func sameOrdered(a, b []string) bool { return strings.Join(a, "\x00") == strings.Join(b, "\x00") }
func (a *app) helper(action string, args ...string) bool {
	_, e := a.run(240*time.Second, nil, a.p(helperPath), append([]string{action}, args...)...)
	return e == nil
}
func (a *app) execute(job object, payload []byte, receipt string) string {
	transaction := a.p(vpnRoot + "/transaction")
	id := str(job["id"])
	expires, _ := integer(job["expires"])
	readEq := func(p, s string) bool { v, e := textFile(p); return e == nil && v == s }
	if job["kind"] == "accept_verified" {
		tid := str(job["transaction_id"])
		if readEq(a.p(vpnRoot+"/completed/"+tid+"/phase"), "accepted") {
			return "verified"
		}
		if expires <= a.now().Unix() {
			return "expired"
		}
		if !readEq(filepath.Join(transaction, "deployment-id"), tid) {
			return "recovery_required"
		}
		if a.helper("accept-id", tid) {
			return "verified"
		}
		return "recovery_required"
	}
	if exists(receipt) {
		prev, e := textFile(receipt)
		if e != nil {
			return "recovery_required"
		}
		if prev == "started" && job["commit"] == true {
			completed := a.p(vpnRoot + "/completed/" + id)
			if readEq(filepath.Join(completed, "phase"), "accepted") && readEq(filepath.Join(completed, "payload.sha256"), str(job["digest"])) {
				return "verified"
			}
			if readEq(filepath.Join(transaction, "phase"), "accepted") && readEq(filepath.Join(transaction, "deployment-id"), id) && readEq(filepath.Join(transaction, "payload.sha256"), str(job["digest"])) && a.helper("accept-id", id) {
				return "verified"
			}
		}
		if has([]string{"verified", "failed", "recovery_required", "expired"}, prev) {
			return prev
		}
		return "recovery_required"
	}
	if expires <= a.now().Unix() {
		return "expired"
	}
	if exists(transaction) {
		return "recovery_required"
	}
	if atomic(receipt, []byte("started")) != nil {
		return "recovery_required"
	}
	action := "prepare-upload"
	args := []string{action, id, str(job["country"])}
	if _, ok := job["target"]; ok {
		args[0] = "prepare-upload-target"
		args = append(args, str(job["target"]), str(job["address"]))
	}
	if _, e := a.run(240*time.Second, payload, a.p(helperPath), args...); e != nil {
		if !exists(transaction) {
			return "failed"
		}
		return "recovery_required"
	}
	deployment := filepath.Join(transaction, "deployment-id")
	for _, delay := range []int{0, 10, 20, 30, 40, 50} {
		if delay > 0 {
			a.sleep(time.Duration(delay) * time.Second)
		}
		if !readEq(deployment, id) {
			return "recovery_required"
		}
		if a.helper("verify") && readEq(deployment, id) {
			if job["commit"] != true || a.helper("accept") {
				return "verified"
			}
			return "recovery_required"
		}
	}
	return "recovery_required"
}
func (a *app) topology() object {
	out := object{"active": nil, "slots": object{}, "transaction": nil, "delivery_ready": false, "binding_ready": true, "controller_slots": []string{"awg_main", "awg_backup"}, "failover_slots": []string{}, "order_size": 0, "prepared_revision": 0}
	ss := obj(out["slots"])
	out["observed"] = a.observedInterfaces()
	out["prune_ready"] = true
	for _, s := range slots {
		v, e := a.observe(s)
		if e != nil {
			continue
		}
		h, e := a.text("awg", "show", s, "latest-handshakes")
		verified := false
		if e == nil {
			f := strings.Fields(h)
			if len(f) == 2 {
				var epoch int64
				fmt.Sscan(f[1], &epoch)
				verified = epoch > 0 && epoch <= a.now().Unix() && a.now().Unix()-epoch <= 180
			}
		}
		v["verified"] = verified
		ss[s] = v
	}
	if section, e := textFile(a.p(vpnRoot + "/podkop-section")); e == nil && valid(`[A-Za-z0-9_]+`, section) {
		active, e := a.text("uci", "-q", "get", "podkop."+section+".interface")
		if e == nil && ss[active] != nil {
			out["active"] = active
		}
	}
	if status, e := a.text(a.p(helperPath), "status"); e == nil {
		m := regexpTransaction.FindStringSubmatch(status)
		if len(m) == 2 {
			out["transaction"] = m[1]
		}
	}
	if id, e := textFile(a.p(vpnRoot + "/transaction/deployment-id")); e == nil && valid(`[a-f0-9]{32}`, id) {
		out["transaction_id"] = id
	}
	out["delivery_ready"] = exists(a.p(helperPath)) && exists(a.p(vpnRoot+"/adapter")) && exists(a.p(vpnRoot+"/podkop-section"))
	if p, e := load(a.p(vpnRoot + "/slot-preparation.json")); e == nil {
		out["preparation"] = p
	}
	if c, e := load(a.p(configPath)); e == nil {
		for _, key := range []string{"received_revision", "apply_failed_revision"} {
			if n,ok := integer(c[key]); ok && n >= 0 { out[key] = n }
		}
		if _, ok := integer(c["binding_failed_revision"]); ok {
			out["binding_failed_revision"] = c["binding_failed_revision"]
		}
		if n, ok := integer(c["prepared_revision"]); ok {
			out["prepared_revision"] = n
		}
	}
	if f, e := read(a.p("/usr/bin/podkop-awg-failover")); e == nil && bytes.Contains(prefix512(f), []byte(`if [ "${1:-}" = --capabilities ]; then`)) {
		if v, e := a.text(a.p("/usr/bin/podkop-awg-failover"), "--capabilities"); e == nil {
			out["failover_slots"] = strings.Fields(v)
		}
	}
	if ack, e := load(a.p(vpnRoot + "/order-applied.json")); e == nil {
		if b, e := read(a.p("/etc/podkop-awg-failover.conf")); e == nil && ack["digest"] == hash(b) {
			if size, ok := integer(ack["size"]); ok && (size == 2 || size == 3) {
				out["order_size"] = size
				out["order"] = ack["order"]
			}
		}
	}
	if v, e := a.text(a.p(helperPath), "capabilities"); e == nil {
		filtered := []string{}
		for _, s := range strings.Fields(v) {
			if has(slots, s) {
				filtered = append(filtered, s)
			}
		}
		out["controller_slots"] = filtered
	}
	if ack,e := load(a.p(vpnRoot+"/plan-applied.json")); e == nil && equalValues(ack["order"],out["order"]) && equalValues(ack["slots"],profileSnapshot(ss)) {
		if n,ok := integer(ack["revision"]); ok && n > 0 { out["applied_revision"] = n }
	}
	return out
}
func profileSnapshot(ss object) object {
	result := object{}
	for name,value := range ss {
		v := obj(value); item := object{}
		for _,key := range []string{"host","port","address","fingerprint"} { item[key] = v[key] }
		result[name] = item
	}
	return result
}
func prefix512(b []byte) []byte {
	if len(b) > 512 {
		return b[:512]
	}
	return b
}
// applyPlannedRebind is deliberately idempotent across successive signed polls.
// Keeping the executor injectable makes repeated-poll behavior testable without
// restarting networking services in unit tests.
func (a *app) applyPlannedRebind(config object, revision any, spec object, execute func(object) error) error {
	encoded, e := canonical(spec)
	if e != nil {
		return e
	}
	digest := hash(encoded)
	if config["binding_applied_revision"] == revision {
		// A signed revision cannot be reused with a different rebind payload.
		if config["binding_applied_digest"] != digest {
			return errStopped
		}
		return nil
	}
	if config["binding_failed_revision"] == revision {
		return nil
	}
	if e = execute(spec); e != nil {
		if e == errBusy {
			return nil
		}
		config["binding_failed_revision"] = revision
		return save(a.p(configPath), config)
	}
	// Persist before returning to the loop; polling the same plan again
	// must not restart Podkop or failover.
	config["binding_applied_revision"] = revision
	config["binding_applied_digest"] = digest
	delete(config, "binding_failed_revision")
	return save(a.p(configPath), config)
}

func (a *app) poll() error {
	config, e := load(a.p(configPath))
	if os.IsNotExist(e) {
		config, e = a.register()
	}
	if e != nil {
		return e
	}
	role := str(config["router"])
	if config["router"] != nil {
		if !has(roles, role) {
			return errStopped
		}
		id, e := textFile(a.p(vpnRoot + "/router-id"))
		if e != nil || id != role {
			return errStopped
		}
	}
	if e = mkdir(a.p(statePath)); e != nil {
		return e
	}
	unlock, e := lock(a.p(statePath + "/poll.lock"))
	if e != nil {
		if e==errBusy{return nil};return e
	}
	defer unlock()
	response, e := a.call(config, "poll", object{"topology": a.topology()})
	if e != nil {
		return e
	}
	if _,present:=response["job"];!present{return errStopped}
	if config["device_id"] != nil && response["assignment"] != nil {
		assignment := str(response["assignment"])
		if !has(roles, assignment) || (role != "" && role != assignment) {
			return errStopped
		}
		p := a.p(vpnRoot + "/router-id")
		if exists(p) {
			id, e := textFile(p)
			if e != nil || id != assignment {
				return errStopped
			}
		} else if e = exclusive(p, []byte(assignment+"\n")); e != nil {
			return e
		}
		if role != assignment {
			role = assignment
			config["router"] = assignment
			if e = save(a.p(configPath), config); e != nil {
				return e
			}
		}
	}
	plan, e := verifyPlan(config, response, a.now().Unix())
	if e != nil {
		return e
	}
	if plan != nil {
		config["received_revision"] = plan["revision"]
		if e = save(a.p(configPath),config); e != nil { return e }
	}
	prepareRole := ""
	if response["prepare_slots"] == true {
		prepareRole = role
	}
	backup2 := false
	if plan != nil {
		ss, _ := stringsOf(plan["slots"])
		backup2 = has(ss, "awg_backup2")
	}
	status, e := a.prepareSlots(prepareRole, backup2)
	if e != nil {
		return e
	}
	if plan != nil && prepareRole != "" {
		ss, _ := stringsOf(plan["slots"])
		if status["phase"] == "ready" && sameSet(keys(obj(status["slots"])), ss) {
			config["prepared_revision"] = plan["revision"]
			if e = save(a.p(configPath), config); e != nil {
				return e
			}
		}
		if rebind := obj(plan["rebind"]); rebind != nil {
			return a.applyPlannedRebind(config, plan["revision"], rebind, a.rebind)
		}
	}
	if plan != nil && plan["order"] != nil {
		order, _ := stringsOf(plan["order"])
		for name,expected:=range obj(plan["expected"]) {
			actual,err:=a.observe(name)
			if err!=nil || !equalValues(actual,expected) { return errStopped }
		}
		if !a.helper("set-order", strings.Join(order, ",")) {
			config["apply_failed_revision"] = plan["revision"]
			if e = save(a.p(configPath),config); e != nil { return e }
			return errStopped
		}
		observed := a.topology()
		if plan["remove_backup2"]==true {
			if e=a.pruneBackup2(); e!=nil {
				if e==errBusy { return nil }
				config["apply_failed_revision"]=plan["revision"]
				if saveErr:=save(a.p(configPath),config);saveErr!=nil{return saveErr};return e
			}
			observed=a.topology()
		}
		complete:=plan["expected"]!=nil
		for _,slot:=range order { if obj(observed["slots"])[slot]==nil { complete=false } }
		for name,expected:=range obj(plan["expected"]) {
			if !equalValues(profileSnapshot(obj(observed["slots"]))[name],expected) { complete=false }
		}
		if complete && equalValues(observed["order"],plan["order"]) {
			ack := object{"revision":plan["revision"],"order":observed["order"],"slots":profileSnapshot(obj(observed["slots"]))}
			if e = save(a.p(vpnRoot+"/plan-applied.json"),ack); e != nil { return e }
			delete(config,"apply_failed_revision")
			if e = save(a.p(configPath),config); e != nil { return e }
		}
	}
	if response["job"] == nil {
		return nil
	}
	if role == "" || !exists(a.p(helperPath)) {
		return errStopped
	}
	job, payload, e := verifyJob(config, response)
	if e != nil {
		return e
	}
	receipt := a.p(statePath + "/" + str(job["id"]))
	result := ""
	if plan != nil && job["commit"] == true && job["revision"] != plan["revision"] {
		result = "expired"
	} else {
		expires,_:=integer(job["expires"])
		if expires>a.now().Unix() && !exists(receipt) && job["kind"]!="accept_verified" {
			if e=a.prepareReplacement(job);e!=nil {
				if e==errBusy{return nil}
				result="failed"
				if exists(a.p(vpnRoot+"/replacement-"+str(job["id"]))){result="recovery_required"}
			}
		}
		if result=="" { result = a.execute(job, payload, receipt) }
	}
	if plan!=nil && job["commit"]==true && (result=="failed" || result=="recovery_required") {
		config["apply_failed_revision"]=plan["revision"]
		if e=save(a.p(configPath),config);e!=nil{return e}
	}
	if e = atomic(receipt, []byte(result)); e != nil {
		return e
	}
	_, e = a.call(config, "result", object{"id": job["id"], "status": result})
	return e
}
