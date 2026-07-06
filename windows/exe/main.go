// u4025qw.exe — switch the input source of a Dell U4025QW via DDC/CI.
//
// Uses the Windows Monitor Configuration API (dxva2.dll), which ships with
// Windows, through the Go stdlib syscall interface — no cgo, no external
// modules, no admin rights. Intended for WDAC-locked machines where the
// binary is allowlisted by hash (see ../../README.md).
//
//	u4025qw <input|alias>   switch input (dp, hdmi, usbc; aliases tb linux work mac)
//	u4025qw status          show the currently active input
//	u4025qw toggle          toggle between dp and usbc
package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"syscall"
	"unsafe"
)

// VCP 0x60 (Input Source) values, verified against the monitor's capabilities
// report on 2026-07-05: 0x0f DisplayPort, 0x11 HDMI, 0x19 Thunderbolt/USB-C.
var inputs = map[string]uint32{
	"dp":   0x0f,
	"hdmi": 0x11,
	"usbc": 0x19,
}

var aliases = map[string]string{
	"tb":    "usbc",
	"linux": "dp",
	"work":  "usbc",
	"mac":   "usbc",
}

const (
	toggleA = "dp"
	toggleB = "usbc"
	vcpCode = 0x60
)

var (
	user32                          = syscall.NewLazyDLL("user32.dll")
	dxva2                           = syscall.NewLazyDLL("dxva2.dll")
	procEnumDisplayMonitors         = user32.NewProc("EnumDisplayMonitors")
	procGetNumberOfPhysicalMonitors = dxva2.NewProc("GetNumberOfPhysicalMonitorsFromHMONITOR")
	procGetPhysicalMonitors         = dxva2.NewProc("GetPhysicalMonitorsFromHMONITOR")
	procGetVCPFeature               = dxva2.NewProc("GetVCPFeatureAndVCPFeatureReply")
	procSetVCPFeature               = dxva2.NewProc("SetVCPFeature")
	procDestroyPhysicalMonitor      = dxva2.NewProc("DestroyPhysicalMonitor")
)

// PHYSICAL_MONITOR: HANDLE (8) + WCHAR[128] (256) = 264 bytes on x64.
type physicalMonitor struct {
	handle      syscall.Handle
	description [128]uint16
}

func enumHMONITORs() []uintptr {
	var handles []uintptr
	cb := syscall.NewCallback(func(hMon, _, _, _ uintptr) uintptr {
		handles = append(handles, hMon)
		return 1 // keep enumerating
	})
	procEnumDisplayMonitors.Call(0, 0, cb, 0)
	return handles
}

// physicalMonitors returns every physical monitor behind every HMONITOR.
// The caller must destroy each handle.
func physicalMonitors() []physicalMonitor {
	var all []physicalMonitor
	for _, hMon := range enumHMONITORs() {
		var count uint32
		if r, _, _ := procGetNumberOfPhysicalMonitors.Call(hMon,
			uintptr(unsafe.Pointer(&count))); r == 0 || count == 0 {
			continue
		}
		mons := make([]physicalMonitor, count)
		if r, _, _ := procGetPhysicalMonitors.Call(hMon, uintptr(count),
			uintptr(unsafe.Pointer(&mons[0]))); r == 0 {
			continue
		}
		all = append(all, mons...)
	}
	return all
}

func readInput(h syscall.Handle) (uint32, bool) {
	var current, max uint32
	r, _, _ := procGetVCPFeature.Call(uintptr(h), vcpCode, 0,
		uintptr(unsafe.Pointer(&current)), uintptr(unsafe.Pointer(&max)))
	return current, r != 0
}

func setInput(h syscall.Handle, value uint32) bool {
	r, _, _ := procSetVCPFeature.Call(uintptr(h), vcpCode, uintptr(value))
	return r != 0
}

func nameOf(value uint32) string {
	for name, v := range inputs {
		if v == value {
			return name
		}
	}
	return "unknown"
}

// forEachDdcMonitor runs fn on every monitor that answers a DDC read of the
// input-source feature (the laptop's internal panel does not, so this targets
// the external Dell). It reports whether any monitor responded.
func forEachDdcMonitor(fn func(h syscall.Handle, current uint32)) bool {
	mons := physicalMonitors()
	if len(mons) == 0 {
		die("no monitors found")
	}
	defer func() {
		for _, m := range mons {
			procDestroyPhysicalMonitor.Call(uintptr(m.handle))
		}
	}()
	responded := false
	for _, m := range mons {
		if current, ok := readInput(m.handle); ok {
			responded = true
			fn(m.handle, current)
		}
	}
	return responded
}

func die(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "error: "+format+"\n", a...)
	os.Exit(1)
}

func knownNames() string {
	names := make([]string, 0, len(inputs)+len(aliases))
	for k := range inputs {
		names = append(names, k)
	}
	for k := range aliases {
		names = append(names, k)
	}
	sort.Strings(names)
	return strings.Join(names, " ")
}

func switchTo(name string) {
	value := inputs[name]
	fmt.Printf("switching to %s (0x%02x)\n", name, value)
	if !forEachDdcMonitor(func(h syscall.Handle, _ uint32) {
		if !setInput(h, value) {
			die("SetVCPFeature failed")
		}
	}) {
		die("no DDC/CI-capable monitor responded (external display connected and awake?)")
	}
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: u4025qw <input|alias|status|toggle>")
		fmt.Fprintf(os.Stderr, "inputs: %s\n", knownNames())
		os.Exit(1)
	}

	switch cmd := os.Args[1]; cmd {
	case "status":
		if !forEachDdcMonitor(func(_ syscall.Handle, current uint32) {
			fmt.Printf("active input: %s (0x%02x)\n", nameOf(current), current)
		}) {
			die("no response from monitor (external display connected and awake?)")
		}
	case "toggle":
		target := toggleA
		if !forEachDdcMonitor(func(_ syscall.Handle, current uint32) {
			if current == inputs[toggleA] {
				target = toggleB
			}
		}) {
			die("no response from monitor (external display connected and awake?)")
		}
		switchTo(target)
	default:
		name := cmd
		if a, ok := aliases[name]; ok {
			name = a
		}
		if _, ok := inputs[name]; !ok {
			die("unknown input %q (know: %s)", cmd, knownNames())
		}
		switchTo(name)
	}
}
