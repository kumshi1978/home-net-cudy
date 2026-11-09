package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
	"unicode/utf8"
)

var errStopped = errors.New("operation stopped; inspect the local recovery record")
var errBusy = errors.New("maintenance busy")
var regexpTransaction = regexp.MustCompile(`(?m)^TRANSACTION_STATE='([a-z-]+)'$`)
var slots = []string{"awg_main", "awg_backup", "awg_backup2"}
var roles = []string{"apartment-main", "apartment-backup", "dacha-main", "dacha-backup"}

type object = map[string]any
type app struct {
	root  string
	run   func(time.Duration, []byte, string, ...string) ([]byte, error)
	now   func() time.Time
	sleep func(time.Duration)
}

func newApp(root string) *app {
	a := &app{root: root, now: time.Now, sleep: time.Sleep}
	a.run = runCommand
	return a
}
func (a *app) p(s string) string {
	// OpenWrt deliberately links /var to /tmp. Resolve only this fixed system
	// alias; arbitrary symlink ancestors remain forbidden for private state.
	if s=="/var/run" { s="/tmp/run" } else if strings.HasPrefix(s,"/var/run/") { s="/tmp/run/"+strings.TrimPrefix(s,"/var/run/") }
	if a.root == "" {
		return s
	}
	return filepath.Join(a.root, strings.TrimPrefix(s, "/"))
}
func runCommand(d time.Duration, input []byte, name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()
	c := exec.CommandContext(ctx, name, args...)
	c.Stdin = bytes.NewReader(input)
	c.Stderr = io.Discard
	out, e := c.Output()
	if e != nil {
		return nil, errStopped
	}
	return out, nil
}
func (a *app) cmd(name string, args ...string) ([]byte, error) {
	return a.run(60*time.Second, nil, name, args...)
}
func (a *app) text(name string, args ...string) (string, error) {
	b, e := a.cmd(name, args...)
	return strings.TrimSpace(string(b)), e
}
func hash(b []byte) string         { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func valid(pattern, s string) bool {
	r, err := regexp.Compile("^(?:" + pattern + ")$")
	return err == nil && r.MatchString(s)
}
func has(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
func read(path string) ([]byte, error) {
	if e := safePath(path); e != nil {
		return nil, e
	}
	return os.ReadFile(path)
}
func textFile(path string) (string, error) {
	b, e := read(path)
	return strings.TrimSpace(string(b)), e
}
func within(path,base string)bool{rel,e:=filepath.Rel(filepath.Clean(base),filepath.Clean(path));return e==nil&&rel!="."&&rel!=".."&&!strings.HasPrefix(rel,".."+string(filepath.Separator))&&!filepath.IsAbs(rel)}
func readLimited(path string,n int64)([]byte,error){if e:=safePath(path);e!=nil{return nil,e};f,e:=os.Open(path);if e!=nil{return nil,e};defer f.Close();b,e:=io.ReadAll(io.LimitReader(f,n+1));if e!=nil||int64(len(b))>n{return nil,errStopped};return b,nil}
func exists(path string) bool { _, e := os.Lstat(path); return e == nil }
func safePath(path string) error {
	path = filepath.Clean(path)
	for {
		info, e := os.Lstat(path)
		if e == nil && info.Mode()&os.ModeSymlink != 0 {
			return errStopped
		}
		if e != nil && !os.IsNotExist(e) {
			return errStopped
		}
		p := filepath.Dir(path)
		if p == path {
			return nil
		}
		path = p
	}
}
func mkdir(path string) error {
	if e := safePath(path); e != nil {
		return e
	}
	return os.MkdirAll(path, 0700)
}
func syncDir(path string) error {
	f, e := os.Open(path)
	if e != nil {
		return e
	}
	defer f.Close()
	return f.Sync()
}
func atomic(path string, b []byte) error {
	if e := safePath(path); e != nil {
		return e
	}
	f, e := os.CreateTemp(filepath.Dir(path), ".home-net-native.")
	if e != nil {
		return e
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if e = f.Chmod(0600); e != nil {
		return e
	}
	if _, e = f.Write(b); e != nil {
		return e
	}
	if e = f.Sync(); e != nil {
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	if e = safePath(path); e != nil {
		return e
	}
	if e = os.Rename(f.Name(), path); e != nil {
		return e
	}
	return syncDir(filepath.Dir(path))
}
func exclusive(path string, b []byte) error {
	if e := safePath(path); e != nil {
		return e
	}
	f, e := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		return e
	}
	_, e = f.Write(b)
	if e == nil {
		e = f.Sync()
	}
	ce := f.Close()
	if e != nil {
		return e
	}
	if ce != nil {
		return ce
	}
	return syncDir(filepath.Dir(path))
}
func decode(b []byte) (object, error) {
	if !utf8.Valid(b) {
		return nil, errStopped
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	var v object
	if e := d.Decode(&v); e != nil || v == nil {
		return nil, errStopped
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return nil, errStopped
	}
	return v, nil
}
func load(path string) (object, error) {
	b, e := read(path)
	if e != nil {
		return nil, e
	}
	return decode(b)
}
func save(path string, v any) error {
	b, e := canonical(v)
	if e != nil {
		return e
	}
	return atomic(path, b)
}
func str(v any) string { s, _ := v.(string); return s }
func obj(v any) object { o, _ := v.(map[string]any); return o }
func integer(v any) (int64, bool) {
	n, ok := v.(json.Number)
	if !ok || !valid(`-?(?:0|[1-9][0-9]*)`, string(n)) {
		return 0, false
	}
	i, e := n.Int64()
	return i, e == nil
}
func stringsOf(v any) ([]string, bool) {
	vs, ok := v.([]any)
	if !ok {
		return nil, false
	}
	out := make([]string, len(vs))
	for i, x := range vs {
		s, ok := x.(string)
		if !ok {
			return nil, false
		}
		out[i] = s
	}
	return out, true
}
func exactKeys(v object, names ...string) bool {
	if len(v) != len(names) {
		return false
	}
	for _, n := range names {
		if _, ok := v[n]; !ok {
			return false
		}
	}
	return true
}
func keys(v object) []string {
	out := make([]string, 0, len(v))
	for k := range v {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
func sameSet(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	x := append([]string{}, a...)
	y := append([]string{}, b...)
	sort.Strings(x)
	sort.Strings(y)
	return strings.Join(x, "\x00") == strings.Join(y, "\x00")
}
func equalValues(a, b any) bool {
	x, e := canonical(a)
	if e != nil {
		return false
	}
	y, e := canonical(b)
	return e == nil && bytes.Equal(x, y)
}
func unique(a []string) bool {
	m := map[string]bool{}
	for _, s := range a {
		if m[s] {
			return false
		}
		m[s] = true
	}
	return true
}

// Match Python json.dumps(sort_keys=True,separators=(",",":"),ensure_ascii=True).
// In particular, encoding/json's HTML escaping and raw Unicode are not the wire format.
func canonical(v any) ([]byte, error) {
	var b bytes.Buffer
	var emit func(any) error
	quote := func(s string) error {
		if !utf8.ValidString(s) {
			return errStopped
		}
		b.WriteByte('"')
		for _, r := range s {
			switch r {
			case '"', '\\':
				b.WriteByte('\\')
				b.WriteRune(r)
			case '\b':
				b.WriteString(`\b`)
			case '\f':
				b.WriteString(`\f`)
			case '\n':
				b.WriteString(`\n`)
			case '\r':
				b.WriteString(`\r`)
			case '\t':
				b.WriteString(`\t`)
			default:
				if r < 32 || r > 126 {
					if r <= 0xffff {
						fmt.Fprintf(&b, `\u%04x`, r)
					} else {
						x, y := utf16.EncodeRune(r)
						fmt.Fprintf(&b, `\u%04x\u%04x`, x, y)
					}
				} else {
					b.WriteRune(r)
				}
			}
		}
		b.WriteByte('"')
		return nil
	}
	emit = func(x any) error {
		switch t := x.(type) {
		case nil:
			b.WriteString("null")
		case bool:
			if t {
				b.WriteString("true")
			} else {
				b.WriteString("false")
			}
		case string:
			return quote(t)
		case json.Number:
			n, ok := integer(t); if !ok {
				return errStopped
			}
			b.WriteString(strconv.FormatInt(n,10))
		case int:
			b.WriteString(strconv.Itoa(t))
		case int64:
			b.WriteString(strconv.FormatInt(t, 10))
		case []string:
			b.WriteByte('[')
			for i, s := range t {
				if i > 0 {
					b.WriteByte(',')
				}
				if e := quote(s); e != nil {
					return e
				}
			}
			b.WriteByte(']')
		case []any:
			b.WriteByte('[')
			for i, s := range t {
				if i > 0 {
					b.WriteByte(',')
				}
				if e := emit(s); e != nil {
					return e
				}
			}
			b.WriteByte(']')
		case map[string]any:
			b.WriteByte('{')
			for i, k := range keys(t) {
				if i > 0 {
					b.WriteByte(',')
				}
				if e := quote(k); e != nil {
					return e
				}
				b.WriteByte(':')
				if e := emit(t[k]); e != nil {
					return e
				}
			}
			b.WriteByte('}')
		default:
			return errStopped
		}
		return nil
	}
	if e := emit(v); e != nil {
		return nil, e
	}
	return b.Bytes(), nil
}
