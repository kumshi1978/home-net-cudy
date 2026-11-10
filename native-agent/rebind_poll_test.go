package main

import (
	"encoding/json"
	"path/filepath"
	"testing"
)

func TestPlannedRebindIsExecutedOnceAcrossPolls(t *testing.T) {
	a := newApp(t.TempDir())
	if e := mkdir(filepath.Dir(a.p(configPath))); e != nil { t.Fatal(e) }
	revision := json.Number("4")
	plan := object{"revision": revision, "mapping": object{"awg_main": "awg_backup"}}
	config := object{"received_revision": revision, "prepared_revision": revision, "apply_failed_revision": revision}
	calls := 0
	run := func(object) error { calls++; return nil }
	if e := a.applyPlannedRebind(config, revision, plan, run, func(object) bool { return true }); e != nil { t.Fatal(e) }
	if calls != 1 { t.Fatalf("first delivery ran %d times", calls) }
	persisted, e := load(a.p(configPath))
	if e != nil { t.Fatal(e) }
	if persisted["binding_applied_revision"] != revision || persisted["binding_applied_digest"] == nil {
		t.Fatalf("success acknowledgement was not durable: %v", persisted)
	}
	// Model a fresh polling cycle after process restart, using persisted state.
	if e := a.applyPlannedRebind(persisted, revision, plan, run, func(object) bool { return true }); e != nil { t.Fatal(e) }
	if calls != 1 { t.Fatalf("replayed revision restarted services: %d", calls) }
	if persisted["apply_failed_revision"] != revision { t.Fatal("unrelated plan failure was silently cleared") }
}

func TestPlannedRebindRejectsChangedPayloadAtSameRevision(t *testing.T) {
	a := newApp(t.TempDir())
	if e := mkdir(filepath.Dir(a.p(configPath))); e != nil { t.Fatal(e) }
	rev := json.Number("4")
	config := object{}
	one := object{"selected": "awg_main"}
	count := 0
	run := func(object) error { count++; return nil }
	if e := a.applyPlannedRebind(config, rev, one, run, func(object) bool { return true }); e != nil { t.Fatal(e) }
	if e := a.applyPlannedRebind(config, rev, object{"selected": "awg_backup"}, run, func(object) bool { return true }); e == nil {
		t.Fatal("changed signed rebind under an acknowledged revision was accepted")
	}
	if count != 1 { t.Fatal("changed replay mutated network") }
}

func TestPlannedRebindRejectsDriftWithoutReapplying(t *testing.T) {
    a := newApp(t.TempDir())
    if e := mkdir(filepath.Dir(a.p(configPath))); e != nil { t.Fatal(e) }
    rev := json.Number("4")
    spec := object{"revision": rev, "mapping": object{"awg_main": "awg_main"}}
    config := object{}
    calls := 0
    run := func(object) error { calls++; return nil }
    healthy := func(object) bool { return true }
    drift := func(object) bool { return false }
    if e := a.applyPlannedRebind(config, rev, spec, run, healthy); e != nil { t.Fatal(e) }
    if e := a.applyPlannedRebind(config, rev, spec, run, drift); e == nil { t.Fatal("drift must block acknowledgement") }
    if calls != 1 { t.Fatalf("unexpected replay of network mutation: %d", calls) }
    saved, e := load(a.p(configPath))
    if e != nil { t.Fatal(e) }
    if saved["binding_failed_revision"] != rev { t.Fatal("drift failure was not persisted") }
}

func TestPlannedRebindBusyAndFailedAreNotMarkedApplied(t *testing.T) {
	for _, tc := range []struct{ name string; result error; wantCalls int }{
		{"busy", errBusy, 2},
		{"failed", errStopped, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a := newApp(t.TempDir())
			if e := mkdir(filepath.Dir(a.p(configPath))); e != nil { t.Fatal(e) }
			rev := json.Number("4")
			config := object{}
			calls := 0
			run := func(object) error { calls++; return tc.result }
			if e := a.applyPlannedRebind(config, rev, object{"selected": "awg_main"}, run, func(object) bool { return true }); e != nil { t.Fatal(e) }
			if config["binding_applied_revision"] != nil { t.Fatal("failed or busy rebind marked successful") }
			if e := a.applyPlannedRebind(config, rev, object{"selected": "awg_main"}, run, func(object) bool { return true }); e != nil { t.Fatal(e) }
			if calls != tc.wantCalls { t.Fatalf("unexpected retry count %d", calls) }
			if tc.name == "failed" && config["binding_failed_revision"] != rev { t.Fatal("failure guard not persisted") }
		})
	}
}
