package main

import (
	"bytes"
	"filippo.io/age"
	"io"
	"strings"
)

func newIdentityForTest() (*age.X25519Identity, error)                    { return age.GenerateX25519Identity() }
func encryptForTest(w io.Writer, r age.Recipient) (io.WriteCloser, error) { return age.Encrypt(w, r) }
func decryptForTest(b []byte, id age.Identity) ([]byte, error) {
	r, e := age.Decrypt(bytes.NewReader(b), id)
	if e != nil {
		return nil, e
	}
	return io.ReadAll(r)
}

const identityPath = "/etc/home-net/keys/age-identity.txt"

func (a *app) identity() (*age.X25519Identity, error) {
	b, e := readLimited(a.p(identityPath),4096)
	if e != nil {
		return nil, errStopped
	}
	ids, e := age.ParseIdentities(strings.NewReader(string(b)))
	if e != nil || len(ids) != 1 {
		return nil, errStopped
	}
	id, ok := ids[0].(*age.X25519Identity)
	if !ok {
		return nil, errStopped
	}
	return id, nil
}
func (a *app) initIdentity() error {
	p := a.p(identityPath)
	if e := mkdir(a.p("/etc/home-net/keys")); e != nil {
		return e
	}
	if exists(p) {
		_, e := a.identity()
		return e
	}
	id, e := age.GenerateX25519Identity()
	if e != nil {
		return errStopped
	}
	return exclusive(p, []byte(id.String()+"\n"))
}
func (a *app) decrypt(b []byte) ([]byte, error) {
	if len(b) > 65536 || !bytes.HasPrefix(b, []byte("age-encryption.org/v1\n")) {
		return nil, errStopped
	}
	id, e := a.identity()
	if e != nil {
		return nil, e
	}
	r, e := age.Decrypt(bytes.NewReader(b), id)
	if e != nil {
		return nil, errStopped
	}
	out, e := io.ReadAll(io.LimitReader(r, 65537))
	if e != nil || len(out) > 65536 {
		return nil, errStopped
	}
	return out, nil
}
