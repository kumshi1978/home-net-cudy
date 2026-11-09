//go:build linux

package main

import (
 "bytes"
 "os"
 "path/filepath"
 "strings"
 "testing"
 "time"
)

// Exercise persistence with a runtime ListenPort: showconf can include this
// even when the imported client profile left the local port unspecified.
func TestPersistRuntimeListenPort(t *testing.T) {
 for _,collision:=range []bool{false,true} {
  t.Run(map[bool]string{false:"distinct",true:"collision"}[collision],func(t *testing.T) {
   a:=newApp(t.TempDir())
   network:=a.p("/etc/config/network")
   mkdir(filepath.Dir(network));mkdir(a.p(vpnRoot+"/transaction/backup"))
   original:=[]byte("baseline network")
   os.WriteFile(network,original,0600)
   conf:=bytes.Replace(syntheticConf(),[]byte("[Interface]"),[]byte("[Interface]\nListenPort = 42000"),1)
   queried:=false;writes:=0
   a.run=func(_ time.Duration,input []byte,name string,args ...string)([]byte,error) {
    if name=="awg" {
     if sameOrdered(args,[]string{"showconf","awg_backup"}) {return conf,nil}
     if sameOrdered(args,[]string{"show","all","listen-port"}) {
      queried=true
      if collision {return []byte("awg_main\t42000\nawg_backup\t42000\n"),nil}
      return []byte("awg_main\t41000\nawg_backup\t42000\n"),nil
     }
     t.Errorf("unsupported AWG command: %v",args);return nil,errStopped
    }
    if name=="uci" {
     switch strings.Join(args," ") {
     case "changes network":return nil,nil
     case "-q get network.awg_backup.proto":return []byte("amneziawg"),nil
     case "-q show network":return []byte("network.awg_backup=interface\n"),nil
     }
     if len(args)==5&&args[0]=="-c"&&args[4]=="batch" {
      writes++
      if !strings.Contains(string(input),".listen_port='42000'") {t.Fatal("local port lost")}
      return nil,os.WriteFile(filepath.Join(args[1],"network"),[]byte("persisted network"),0600)
     }
    }
    t.Errorf("unexpected command: %s %v",name,args);return nil,errStopped
   }
   err:=a.persist("awg_backup",hash(conf))
   if !queried {t.Fatal("runtime port collision check skipped")}
   current,_:=read(network)
   if collision {
    if err==nil||writes!=0||!bytes.Equal(current,original) {t.Fatal("collision was not non-mutating")}
   } else if err!=nil||writes!=1||string(current)!="persisted network" {t.Fatal("valid runtime port not persisted",err)}
  })
 }
}
