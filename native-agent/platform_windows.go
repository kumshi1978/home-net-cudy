//go:build windows

package main

import (
	"os"
	"syscall"
)

func lock(string) (func(), error) { return nil, errStopped }
func bindDevice(string) func(string, string, syscall.RawConn) error {
	return func(string, string, syscall.RawConn) error { return errStopped }
}
func inheritedLock(string) error   { return errStopped }
func rootUser() bool               { return false }
func terminationSignal() os.Signal { return os.Interrupt }
