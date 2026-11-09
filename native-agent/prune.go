package main

import (
 "bytes"
 "os"
 "path/filepath"
 "strings"
 "time"
)

// Only an explicitly signed two-slot plan may remove this fixed third slot.
func pruneCommands(shown string) ([]string,error) {
 peers := []string{}
 found := false
 for _,line := range strings.Split(shown,"\n") {
  pair := strings.SplitN(line,"=",2)
  if len(pair)!=2 { continue }
  if pair[0]=="network.awg_backup2" {
   if pair[1]!="interface" { return nil,errStopped }; found=true
  }
  if pair[1]=="amneziawg_awg_backup2" || pair[1]=="wireguard_awg_backup2" {
   if !valid(`network\.[A-Za-z0-9_@\[\]]+`,pair[0]) { return nil,errStopped }
   peers=append(peers,pair[0])
  }
 }
 commands:=[]string{}
 for i:=len(peers)-1;i>=0;i-- { commands=append(commands,"delete "+peers[i]) }
 if found { commands=append(commands,"delete network.awg_backup2") }
 return commands,nil
}

func (a *app) pruneBackup2() error {
 unlock,e:=lock(a.p("/var/run/home-net-vpn-maintenance.lock"))
 if e!=nil { return e }; defer unlock()
 if exists(a.p(vpnRoot+"/transaction")) || exists(a.p(vpnRoot+"/rebind-pending")) || exists(a.p(vpnRoot+"/prune-pending")) || a.dirty("network") || a.dirty("podkop") { return errStopped }
 section,e:=textFile(a.p(vpnRoot+"/podkop-section"))
 if e!=nil || !valid(`[A-Za-z0-9_]+`,section) { return errStopped }
 active:=a.get("podkop."+section+".interface")
 if !has(slots[:2],active) { return errStopped }
 shown,e:=a.text("uci","-q","-X","show","network")
 if e!=nil { return e }
 commands,e:=pruneCommands(shown)
 if e!=nil || len(commands)==0 { return e }
 network:=a.p("/etc/config/network")
 original,e:=read(network); if e!=nil { return e }
 replacement,e:=a.edited(network,commands); if e!=nil { return e }
 // Remove the third slot from Failover before deleting its configuration.
 if e=a.setOrder("awg_main,awg_backup"); e!=nil { return e }
 current,e:=read(network)
 if e!=nil || !bytes.Equal(current,original) || a.dirty("network") || a.get("podkop."+section+".interface")!=active { return errStopped }
 pending:=a.p(vpnRoot+"/prune-pending")
 if e=mkdir(pending); e!=nil { return e }
 if e=exclusive(filepath.Join(pending,"network.before"),original); e!=nil { return e }
 if e=atomic(network,replacement); e!=nil { return e }
 if _,e=a.run(30*time.Second,nil,"ubus","call","network","reload"); e!=nil { return errStopped }
 // A failed/restarted cleanup retains its recovery record and is never retried blindly.
 gone:=false
 for attempt:=0;attempt<10;attempt++ {
  observation:=a.observedInterfaces()
  if obj(obj(observation["slots"])["awg_backup2"])["state"]=="missing" { gone=true;break }
  a.sleep(time.Second)
 }
 if !gone { return errStopped }
 if a.get("podkop."+section+".interface")!=active { return errStopped }
 if e=os.Remove(filepath.Join(pending,"network.before")); e!=nil { return e }
 if e=os.Remove(pending); e!=nil { return e }
 return syncDir(filepath.Dir(pending))
}
