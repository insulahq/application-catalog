// nginx-workers: set nginx worker_processes from the container's cgroup CPU limit
// (ceil of cores), then exec nginx. Distroless-friendly: a single static binary,
// no shell. nginx's own `worker_processes auto` counts HOST cores, which badly
// over-provisions CPU-limited pods (e.g. 20 workers in a 0.10-CPU pod on a
// 20-core node); this reads the ACTUAL cgroup CPU limit instead so worker count
// tracks the pod's allocation. Falls back to 1 worker when no limit is detectable.
package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
)

func ceilDiv(q, p int) int {
	w := (q + p - 1) / p
	if w < 1 {
		w = 1
	}
	return w
}

func readInt(path string) (int, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return 0, false
	}
	return n, true
}

func workers() (int, string) {
	// cgroup v2: /sys/fs/cgroup/cpu.max = "<quota> <period>" | "max <period>"
	if b, err := os.ReadFile("/sys/fs/cgroup/cpu.max"); err == nil {
		f := strings.Fields(strings.TrimSpace(string(b)))
		if len(f) == 2 && f[0] != "max" {
			if q, err1 := strconv.Atoi(f[0]); err1 == nil {
				if p, err2 := strconv.Atoi(f[1]); err2 == nil && p > 0 && q > 0 {
					return ceilDiv(q, p), fmt.Sprintf("cgroup v2 %d/%d", q, p)
				}
			}
		}
		return 1, "cgroup v2 unlimited -> 1"
	}
	// cgroup v1 fallback
	if q, ok := readInt("/sys/fs/cgroup/cpu/cpu.cfs_quota_us"); ok && q > 0 {
		if p, ok := readInt("/sys/fs/cgroup/cpu/cpu.cfs_period_us"); ok && p > 0 {
			return ceilDiv(q, p), fmt.Sprintf("cgroup v1 %d/%d", q, p)
		}
	}
	return 1, "no cpu limit detected -> 1"
}

func main() {
	w, why := workers()
	fmt.Fprintf(os.Stderr, "[nginx-workers] worker_processes=%d (%s)\n", w, why)
	argv := []string{
		"/usr/bin/nginx", "-c", "/etc/nginx/nginx.conf", "-e", "/dev/stderr",
		"-g", "worker_processes " + strconv.Itoa(w) + "; daemon off;",
	}
	if err := syscall.Exec(argv[0], argv, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "[nginx-workers] exec nginx failed: %v\n", err)
		os.Exit(1)
	}
}
