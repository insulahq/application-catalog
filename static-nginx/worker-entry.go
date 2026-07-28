// nginx-workers: (1) optionally wire up a tenant-supplied NGINX config directory
// from the NGINX_CONF_DIR env var, then (2) set nginx worker_processes from the
// container's cgroup CPU limit (ceil of cores) and exec nginx.
//
// Distroless-friendly: a single static binary, no shell.
//
// (2) exists because nginx's own `worker_processes auto` counts HOST cores, which
// badly over-provisions CPU-limited pods (e.g. 20 workers in a 0.10-CPU pod on a
// 20-core node); reading the ACTUAL cgroup limit makes the worker count track the
// pod's allocation. Falls back to 1 worker when no limit is detectable.
package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

// README seeded into the tenant's config directory so guidance is present where
// they work (via SFTP / file manager).
//
//go:embed config-readme.txt
var readme string

const (
	docRoot  = "/var/www/html"
	glueDir  = "/etc/nginx/user-include"
	glueFile = "/etc/nginx/user-include/00-user-config.conf"
)

// setupUserConfig wires NGINX_CONF_DIR into the server block, if set.
//
// Empty/unset -> remove any stale glue and do nothing (plain default config).
// Set to <dir> -> create <dir>, seed its README if missing, and write a glue
// file (included inside the server block) that includes <dir>/*.conf. If <dir>
// lives under the web root, the glue also refuses to serve it so tenant config
// is never publicly downloadable.
func setupUserConfig() {
	dir := strings.TrimSpace(os.Getenv("NGINX_CONF_DIR"))
	if dir == "" {
		// Feature off: ensure no leftover include from a previous config.
		_ = os.Remove(glueFile)
		return
	}
	dir = filepath.Clean(dir)
	if dir == docRoot {
		fmt.Fprintf(os.Stderr, "[nginx-workers] NGINX_CONF_DIR must not be the web root (%s); ignoring\n", docRoot)
		_ = os.Remove(glueFile)
		return
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "[nginx-workers] cannot create NGINX_CONF_DIR %s: %v\n", dir, err)
		_ = os.Remove(glueFile)
		return
	}

	// Seed the README if the tenant hasn't added one — never clobber.
	readmePath := filepath.Join(dir, "README.txt")
	if _, err := os.Stat(readmePath); os.IsNotExist(err) {
		if err := os.WriteFile(readmePath, []byte(readme), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "[nginx-workers] README seed failed: %v\n", err)
		} else {
			fmt.Fprintf(os.Stderr, "[nginx-workers] seeded %s\n", readmePath)
		}
	}

	// Build the glue that nginx.default.conf includes inside its server block.
	var b strings.Builder
	if rel, err := filepath.Rel(docRoot, dir); err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		// dir is inside the web root -> make sure it is never served.
		fmt.Fprintf(&b, "location ^~ /%s/ { return 404; }\n", filepath.ToSlash(rel))
	}
	fmt.Fprintf(&b, "include %s/*.conf;\n", dir)

	if err := os.MkdirAll(glueDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "[nginx-workers] cannot prepare %s: %v\n", glueDir, err)
		return
	}
	if err := os.WriteFile(glueFile, []byte(b.String()), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "[nginx-workers] cannot write include glue: %v\n", err)
		return
	}
	fmt.Fprintf(os.Stderr, "[nginx-workers] NGINX_CONF_DIR=%s wired into the server block\n", dir)
}

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
	setupUserConfig()
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
