//go:build linux

package main

import (
	"errors"
	"golang.org/x/sys/unix"
	"os"
	"syscall"
)

func lock(path string) (func(), error) {
	if e := safePath(path); e != nil {
		return nil, e
	}
	f, e := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0600)
	if e != nil {
		return nil, e
	}
	if e = unix.Flock(int(f.Fd()), unix.LOCK_EX|unix.LOCK_NB); e != nil {
		f.Close()
		if errors.Is(e,unix.EWOULDBLOCK)||errors.Is(e,unix.EAGAIN){return nil,errBusy};return nil,errStopped
	}
	return func() { unix.Flock(int(f.Fd()), unix.LOCK_UN); f.Close() }, nil
}
func bindDevice(device string) func(string, string, syscall.RawConn) error {
	return func(_, _ string, c syscall.RawConn) error {
		var se error
		e := c.Control(func(fd uintptr) { se = unix.SetsockoptString(int(fd), unix.SOL_SOCKET, unix.SO_BINDTODEVICE, device) })
		if e != nil {
			return e
		}
		return se
	}
}
func inheritedLock(path string) error {
	if e := safePath(path); e != nil {
		return e
	}
	var fd, st unix.Stat_t
	if unix.Fstat(9, &fd) != nil || unix.Stat(path, &st) != nil || fd.Dev != st.Dev || fd.Ino != st.Ino {
		return errStopped
	}
	return unix.Flock(9, unix.LOCK_EX|unix.LOCK_NB)
}
func rootUser() bool               { return os.Geteuid() == 0 }
func terminationSignal() os.Signal { return syscall.SIGTERM }
