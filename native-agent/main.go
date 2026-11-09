package main

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/signal"
	"time"
)

var version = "0.1.0-rc1"

func (a *app) dispatch(args []string) error {
	if len(args) == 0 {
		return errStopped
	}
	switch args[0] {
	case "version":
		fmt.Println(version)
		return nil
	case "self-test":
		if len(args) != 1 {
			return errStopped
		}
		return cryptoSelfTest()
	case "identity-init":
		if len(args) != 1 {
			return errStopped
		}
		return a.initIdentity()
	case "recipient":
		if len(args) != 1 {
			return errStopped
		}
		id, e := a.identity()
		if e != nil {
			return e
		}
		fmt.Println(id.Recipient().String())
		return nil
	case "decrypt":
		if len(args) != 3 || !within(args[1], a.p("/tmp")) || !within(args[2], a.p("/tmp")) {
			return errStopped
		}
		b, e := readLimited(args[1],65536)
		if e != nil {
			return e
		}
		out, e := a.decrypt(b)
		if e != nil {
			return e
		}
		return exclusive(args[2], out)
	case "prepare-slots":
		if len(args) > 3 {
			return errStopped
		}
		role := ""
		backup2 := false
		if len(args) > 1 {
			role = args[1]
		}
		if len(args) == 3 {
			if args[2] != "--backup2" {
				return errStopped
			}
			backup2 = true
		}
		s, e := a.prepareSlots(role, backup2)
		if e != nil {
			return e
		}
		if s["phase"] == "blocked" {
			return errStopped
		}
		return nil
	case "persist":
		if e := inheritedLock(a.p("/var/run/home-net-vpn-maintenance.lock")); e != nil {
			return e
		}
		if len(args) == 2 && args[1] == "--restore" {
			return a.restorePersisted()
		}
		if len(args) == 3 && args[1] == "--order" {
			return a.setOrder(args[2])
		}
		if len(args) == 3 {
			return a.persist(args[1], args[2])
		}
		return errStopped
	case "rebind":
		if len(args) != 2 || len(args[1]) > 8192 {
			return errStopped
		}
		s, e := decode([]byte(args[1]))
		if e != nil {
			return e
		}
		return a.rebind(s)
	case "topology":
		if len(args) != 1 {
			return errStopped
		}
		b, e := canonical(a.topology())
		if e == nil {
			fmt.Println(string(b))
		}
		return e
	case "agent":
		if len(args) != 1 {
			return errStopped
		}
		return a.poll()
	default:
		return errStopped
	}
}
func cryptoSelfTest() error {
	id, e := newIdentityForTest()
	if e != nil {
		return e
	}
	var b bytes.Buffer
	w, e := encryptForTest(&b, id.Recipient())
	if e != nil {
		return e
	}
	if _, e = w.Write([]byte("native-agent-self-test")); e != nil {
		return e
	}
	if e = w.Close(); e != nil {
		return e
	}
	out, e := decryptForTest(b.Bytes(), id)
	if e != nil || string(out) != "native-agent-self-test" {
		return errStopped
	}
	return nil
}
func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "HOME NET native agent: invalid invocation")
		os.Exit(1)
	}
	a := newApp("")
	args := os.Args[1:]
	if args[0] != "version" && args[0] != "self-test" && !rootUser() {
		fmt.Fprintln(os.Stderr, "HOME NET native agent: root required")
		os.Exit(1)
	}
	if len(args) == 2 && args[0] == "agent" && args[1] == "--loop" {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, terminationSignal())
		defer stop()
		for ctx.Err() == nil {
			if a.poll() != nil {
				fmt.Fprintln(os.Stderr, "HOME NET native agent: poll requires review")
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(60 * time.Second):
			}
		}
		return
	}
	if e := a.dispatch(args); e != nil {
		fmt.Fprintln(os.Stderr, "HOME NET native agent: operation stopped; inspect local recovery record")
		if e == errBusy {
			os.Exit(75)
		}
		os.Exit(1)
	}
}
