package main

import (
 "bytes"
 "path/filepath"
 "strings"
 "time"
)

// A verified, unexpired job explicitly replaces an inactive profile. A down
// legacy interface must first be made safe to start without its obsolete peers.
func (a *app) prepareReplacement(job object) error {
 target:=str(job["target"])
 if !has(slots,target) { return nil }
 expires,ok:=integer(job["expires"])
 if !ok || expires<=a.now().Unix() { return errStopped }
 unlock,e:=lock(a.p("/var/run/home-net-vpn-maintenance.lock"));if e!=nil{return e};defer unlock()
 section,e:=textFile(a.p(vpnRoot+"/podkop-section"))
 if e!=nil || !valid(`[A-Za-z0-9_]+`,section) || a.get("podkop."+section+".interface")==target { return errStopped }
 if exists(a.p(vpnRoot+"/transaction")) || exists(a.p(vpnRoot+"/rebind-pending")) || exists(a.p(vpnRoot+"/prune-pending")) || a.dirty("network") || a.dirty("podkop") { return errStopped }
 if _,e=a.cmd("ip","link","show","dev",target);e==nil { return nil }
 state:=obj(obj(a.observedInterfaces()["slots"])[target])["state"]
 if state!="down" && state!="disabled" && state!="missing" { return errStopped }
 if a.get("network."+target+".proto")!="amneziawg" || a.get("network."+target+".addresses")!=job["address"] { return errStopped }
 network:=a.p("/etc/config/network")
 original,e:=read(network);if e!=nil{return e}
 shown,e:=a.text("uci","-q","-X","show","network");if e!=nil{return e}
 commands:=[]string{}
 peers:=[]string{}
 options:=map[string]bool{}
 for _,line:=range strings.Split(shown,"\n") {
  pair:=strings.SplitN(line,"=",2);if len(pair)!=2{continue};options[pair[0]]=true
  if pair[1]=="amneziawg_"+target || pair[1]=="wireguard_"+target {
   if !valid(`network\.[A-Za-z0-9_@\[\]]+`,pair[0]){return errStopped};peers=append(peers,pair[0])
  }
 }
 for i:=len(peers)-1;i>=0;i--{commands=append(commands,"delete "+peers[i])}
 for _,option:=range []string{"dns","dns_search","disabled","listen_port"}{if options["network."+target+"."+option]{commands=append(commands,"delete network."+target+"."+option)}}
 commands=append(commands,"set network."+target+".auto='0'","set network."+target+".defaultroute='0'","set network."+target+".peerdns='0'","set network."+target+".home_net_prepared='1'")
 replacement,e:=a.edited(network,commands);if e!=nil{return e}
 if bytes.Equal(original,replacement){return nil}
 backup:=a.p(vpnRoot+"/replacement-"+str(job["id"]))
 if exists(backup){return errStopped}
 if e=mkdir(backup);e!=nil{return e}
 if e=exclusive(filepath.Join(backup,"network.before"),original);e!=nil{return e}
 current,e:=read(network)
 if e!=nil || !bytes.Equal(current,original) || a.dirty("network") || a.get("podkop."+section+".interface")==target{return errStopped}
 if e=atomic(network,replacement);e!=nil{return e}
 _,e=a.run(30*time.Second,nil,"ubus","call","network","reload")
 return e
}
