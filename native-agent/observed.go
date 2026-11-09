package main

import (
 "strconv"
 "strings"
 "time"
)

// Observations are display evidence, never authorization for a profile mutation.
// Keep the strict observe() contract used by controllers separate.
func (a *app) observedInterfaces() object {
 result := object{"version": 1, "sampled_at": a.now().Unix(), "active": nil, "slots": object{}}
 text := func(name string,args ...string)(string,error) {
  b,e:=a.run(5*time.Second,nil,name,args...);return strings.TrimSpace(string(b)),e
 }
 entries := map[string]object{}
 raw, err := a.run(10*time.Second, nil, "ubus", "call", "network.interface", "dump")
 dump, parseErr := decode(raw)
 validDump := err == nil && parseErr == nil
 if validDump {
  list, ok := dump["interface"].([]any)
  validDump = ok
  for _, item := range list {
   entry := obj(item)
   if has(slots, str(entry["interface"])) { entries[str(entry["interface"])] = entry }
  }
 }
 for _, slot := range slots {
  info := object{"state": "unknown", "verified": false}
  obj(result["slots"])[slot] = info
  if !validDump { info["error"] = "interface_status_unavailable"; continue }
  disabled, disabledErr := text("uci", "-q", "get", "network."+slot+".disabled")
  if disabledErr==nil && disabled=="1" { info["state"]="disabled";continue }
  entry, present := entries[slot]
  if !present { info["state"] = "missing"; continue }
  switch {
  case entry["up"] == true: info["state"] = "up"
  case entry["up"] == false: info["state"] = "down"
  default: info["error"] = "interface_status_unavailable"; continue
  }
  if info["state"] != "up" { continue }
  endpoints, e := text("awg", "show", slot, "endpoints")
  if e != nil { info["error"] = "peer_status_unavailable"; continue }
  lines := strings.Fields(endpoints)
  if len(lines)%2 != 0 { info["error"] = "peer_status_unavailable"; continue }
  info["peer_count"] = len(lines)/2
  if len(lines) != 2 { info["error"] = "peer_count_invalid"; continue }
  metadata, e := a.observe(slot)
  if e != nil { info["error"] = "profile_status_unavailable"; continue }
  for k,v := range metadata { info[k] = v }
  handshake, e := text("awg", "show", slot, "latest-handshakes")
  fields := strings.Fields(handshake)
  if e != nil || len(fields) != 2 || fields[0] != lines[0] { info["error"] = "handshake_unavailable"; continue }
  epoch, parseErr := strconv.ParseInt(fields[1],10,64)
  if parseErr != nil || epoch < 0 || epoch > a.now().Unix() { info["error"] = "handshake_unavailable"; continue }
  info["handshake_at"] = epoch
  info["verified"] = epoch > 0 && a.now().Unix()-epoch <= 180
 }
 if section,e := textFile(a.p(vpnRoot+"/podkop-section")); e == nil && valid(`[A-Za-z0-9_]+`, section) {
  if active,e := text("uci", "-q", "get", "podkop."+section+".interface"); e == nil && has(slots,active) {
   result["active"] = active
  } else { result["active_error"] = "active_unavailable" }
 } else { result["active_error"] = "active_unavailable" }
 // Use collection start so a slow collector cannot make old evidence fresh.
 return result
}
