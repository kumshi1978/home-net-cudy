package main

import (
 "encoding/json"
 "fmt"
 "strings"
 "testing"
 "time"
)

func observedFixture(t *testing.T, state string, peers int, handshake int64, broken bool) *app {
 t.Helper()
 a := newApp(t.TempDir())
 a.now = func() time.Time { return time.Unix(1000,0) }
 mkdir(a.p(vpnRoot))
 atomic(a.p(vpnRoot+"/podkop-section"),[]byte("vpn"))
 a.run = func(_ time.Duration, input []byte, name string, args ...string) ([]byte,error) {
  command := name+" "+strings.Join(args," ")
  switch {
  case command == "ubus call network.interface dump":
   if broken { return nil,errStopped }
   if state == "missing" { return []byte(`{"interface":[]}`),nil }
   return []byte(fmt.Sprintf(`{"interface":[{"interface":"awg_main","up":%t}]}`,state=="up")),nil
  case command == "uci -q get network.awg_main.disabled":
   if state == "disabled" { return []byte("1"),nil }; return nil,errStopped
  case command == "uci -q get podkop.vpn.interface": return []byte("awg_backup2"),nil
  case name == "awg" && len(args)==3 && args[0]=="show" && args[1]=="awg_main":
   switch args[2] {
   case "endpoints": return []byte(strings.Repeat("peer 192.0.2.1:4340\n",peers)),nil
   case "public-key": return []byte("synthetic-public-key"),nil
   case "latest-handshakes": return []byte(fmt.Sprintf("peer %d",handshake)),nil
   }
  case command == "ip -4 -o address show dev awg_main": return []byte("1: awg_main inet 10.8.1.2/32 scope global"),nil
  }
  return nil,errStopped
 }
 return a
}

func TestObservedInterfacesKeepEveryState(t *testing.T) {
 for _,state := range []string{"up","down","disabled","missing"} {
  t.Run(state,func(t *testing.T) {
   a := observedFixture(t,state,1,999,false)
   got := a.observedInterfaces()
   all := obj(got["slots"])
   if len(all)!=3 || obj(all["awg_main"])["state"]!=state || got["active"]!="awg_backup2" { t.Fatal(got) }
   if obj(all["awg_main"])["verified"] != (state=="up") { t.Fatal(got) }
   if obj(all["awg_backup"])["state"]!="missing" { t.Fatal(got) }
  })
 }
}

func TestObservedErrorsNeverBecomeVerified(t *testing.T) {
 for _,tc := range []struct{peers int;epoch int64;broken bool;reason string}{
  {2,999,false,"peer_count_invalid"},{0,999,false,"peer_count_invalid"},
  {1,1001,false,"handshake_unavailable"},{1,999,true,"interface_status_unavailable"},
 } {
  a := observedFixture(t,"up",tc.peers,tc.epoch,tc.broken)
  info := obj(obj(a.observedInterfaces()["slots"])["awg_main"])
  if info["verified"]!=false || info["error"]!=tc.reason { t.Fatal(info) }
 }
 for _,epoch := range []int64{0,819} {
  a := observedFixture(t,"up",1,epoch,false)
  if obj(obj(a.observedInterfaces()["slots"])["awg_main"])["verified"]!=false { t.Fatal("old handshake accepted") }
 }
}

func TestConfiguredInactiveInterfaceDoesNotDisappear(t *testing.T) {
 a:=observedFixture(t,"missing",1,999,false)
 original:=a.run
 a.run=func(d time.Duration,input []byte,name string,args ...string)([]byte,error){
  if name=="uci" && strings.Join(args," ")=="-q get network.awg_main" {return []byte("interface"),nil}
  return original(d,input,name,args...)
 }
 info:=obj(obj(a.observedInterfaces()["slots"])["awg_main"])
 if info["state"]!="down" || info["verified"]!=false {t.Fatal(info)}
}

func TestAppliedRevisionRequiresUnchangedProfileAndOrder(t *testing.T) {
 a := observedFixture(t,"up",1,999,false)
 mkdir(a.p("/etc"))
 atomic(a.p("/etc/podkop-awg-failover.conf"),[]byte("synthetic-policy"))
 save(a.p(vpnRoot+"/order-applied.json"),object{"size":2,"order":[]string{"awg_main","awg_backup"},"digest":hash([]byte("synthetic-policy"))})
 first := a.topology()
 save(a.p(vpnRoot+"/plan-applied.json"),object{"revision":7,"order":first["order"],"slots":profileSnapshot(obj(first["slots"]))})
 if a.topology()["applied_revision"]!=int64(7) { t.Fatal("matching receipt lost") }
 atomic(a.p("/etc/podkop-awg-failover.conf"),[]byte("external-policy-change"))
 if a.topology()["applied_revision"]!=nil { t.Fatal("changed policy still applied") }
}

func TestReplacementCommandsClearOldPeersAndUnsafeOptions(t *testing.T) {
 values,e:=parseAWG(syntheticConf());if e!=nil{t.Fatal(e)}
 values["ListenPort"]="42000"
 shown:="network.awg_backup=interface\nnetwork.awg_backup.dns='192.0.2.53'\nnetwork.awg_backup.dns_search='old.invalid'\nnetwork.awg_backup.disabled='1'\nnetwork.old=amneziawg_awg_backup\nnetwork.older=wireguard_awg_backup\nnetwork.unrelated=amneziawg_awg_main\n"
 commands,e:=persistenceCommands("awg_backup",values,shown);if e!=nil{t.Fatal(e)}
 result:=strings.Join(commands,"\n")
 for _,want:=range []string{"delete network.old","delete network.older","delete network.awg_backup.dns","delete network.awg_backup.dns_search","delete network.awg_backup.disabled",".defaultroute='0'",".peerdns='0'",".listen_port='42000'",".endpoint_port='4340'"}{if !strings.Contains(result,want){t.Fatal("missing",want)}}
 if strings.Contains(result,"delete network.unrelated"){t.Fatal("unrelated peer removed")}
 if _,e=persistenceCommands("awg_backup",values,shown+"network.awg_main.listen_port='42000'\n");e==nil{t.Fatal("saved listen port collision accepted")}
 for _,port:=range []string{"0","65536","-1","wrong"}{
  conf:=strings.Replace(string(syntheticConf()),"[Interface]","[Interface]\nListenPort = "+port,1)
  if _,e=parseAWG([]byte(conf));e==nil{t.Fatal("bad listen port accepted",port)}
 }
}

func TestPruneCommandsOnlyDeleteThirdSlotAndItsPeers(t *testing.T) {
 input:="network.awg_backup2=interface\nnetwork.third=amneziawg_awg_backup2\nnetwork.oldthird=wireguard_awg_backup2\nnetwork.keep=amneziawg_awg_backup\nnetwork.awg_backup=interface"
 commands,e:=pruneCommands(input);if e!=nil{t.Fatal(e)}
 if !sameOrdered(commands,[]string{"delete network.oldthird","delete network.third","delete network.awg_backup2"}){t.Fatal(commands)}
 if _,e=pruneCommands("network.awg_backup2=bridge");e==nil{t.Fatal("name conflict accepted")}
 a:=observedFixture(t,"up",1,999,false)
 mkdir(a.p("/tmp/run"))
 if e=a.pruneBackup2();e==nil{t.Fatal("deleted selected third slot")}
}

func TestSignedCleanupAndReceivedRevisionGuards(t *testing.T) {
 config:=object{"signing_key":strings.Repeat("22",32),"received_revision":json.Number("7")}
 plan:=fixtureObject(t,`{"revision":7,"expires":1100,"slots":["awg_main","awg_backup"],"order_size":2,"order":["awg_main","awg_backup"],"remove_backup2":true}`)
 plan["expected"]=fixtureObject(t,`{"awg_main":{"host":"192.0.2.1","port":4340,"address":"10.8.1.1/32","fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"awg_backup":{"host":"192.0.2.2","port":4341,"address":"10.8.1.2/32","fingerprint":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}`)
 response:=object{"plan":plan,"plan_signature":signFixture(t,config,plan)}
 if _,e:=verifyPlan(config,response,1000);e!=nil{t.Fatal(e)}
 plan["revision"]=json.Number("6");response["plan_signature"]=signFixture(t,config,plan)
 if _,e:=verifyPlan(config,response,1000);e==nil{t.Fatal("replayed older received revision")}
 plan["revision"]=json.Number("7");plan["order"]=[]any{"awg_backup","awg_main"};response["plan_signature"]=signFixture(t,config,plan)
 if _,e:=verifyPlan(config,response,1000);e==nil{t.Fatal("cleanup without fixed two-slot order")}
}
