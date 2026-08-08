//go:build integration

package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func freePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = listener.Close() }()
	return listener.Addr().(*net.TCPAddr).Port
}

func docker(t *testing.T, args ...string) []byte {
	t.Helper()
	cmd := exec.Command("docker", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("docker %v: %v\n%s", args, err, output)
	}
	return output
}

func TestDocker(t *testing.T) {
	if err := exec.Command("docker", "version").Run(); err != nil {
		t.Skip("Docker unavailable")
	}
	repoRoot, err := filepath.Abs("..")
	if err != nil {
		t.Fatal(err)
	}
	image := "dotfiles-mcp-go-test:latest"
	build := exec.Command("docker", "build", "-t", image, ".")
	build.Dir = repoRoot
	build.Stdout = io.Discard
	var buildErr bytes.Buffer
	build.Stderr = &buildErr
	if err := build.Run(); err != nil {
		t.Fatalf("docker build: %v\n%s", err, buildErr.String())
	}

	workspace := t.TempDir()
	if err := os.WriteFile(filepath.Join(workspace, "probe.txt"), []byte("probe\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	port := freePort(t)
	name := fmt.Sprintf("dotfiles-mcp-go-test-%d", os.Getpid())
	t.Cleanup(func() { _ = exec.Command("docker", "rm", "-f", name).Run() })
	docker(t, "run", "-d", "--init", "--rm", "--name", name,
		"-p", fmt.Sprintf("127.0.0.1:%d:3000", port),
		"-v", workspace+":/work",
		"-e", "HOST_USER=teo",
		"-e", "HOST_UID="+strconv.Itoa(os.Getuid()),
		"-e", "HOST_GID="+strconv.Itoa(os.Getgid()),
		image)

	base := fmt.Sprintf("http://127.0.0.1:%d", port)
	deadline := time.Now().Add(30 * time.Second)
	for {
		response, err := http.Get(base + "/healthz")
		if err == nil {
			_ = response.Body.Close()
			if response.StatusCode == http.StatusOK {
				break
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("container did not become healthy: %s", docker(t, "logs", name))
		}
		time.Sleep(100 * time.Millisecond)
	}

	client := mcp.NewClient(&mcp.Implementation{Name: "container-test", Version: "0"}, nil)
	session, err := client.Connect(context.Background(), &mcp.StreamableClientTransport{Endpoint: base + "/mcp"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = session.Close() })
	call := func(tool string, arguments map[string]any) *mcp.CallToolResult {
		t.Helper()
		result, err := session.CallTool(context.Background(), &mcp.CallToolParams{Name: tool, Arguments: arguments})
		if err != nil {
			t.Fatal(err)
		}
		return result
	}

	search := decodeStructured[searchOutput](t, call("search_files", map[string]any{"query": "probe"}))
	if len(search.Matches) != 1 {
		t.Fatalf("search: %#v", search)
	}
	patch := "--- a/probe.txt\n+++ b/probe.txt\n@@ -1 +1 @@\n-probe\n+patched\n"
	patched := decodeStructured[patchOutput](t, call("apply_patch", map[string]any{"patch": patch}))
	if !patched.Applied {
		t.Fatal("patch not applied")
	}
	read := decodeStructured[readOutput](t, call("read_path", map[string]any{"path": "probe.txt"}))
	if !strings.Contains(read.Text, "patched") {
		t.Fatalf("read: %#v", read)
	}
	command := decodeStructured[commandOutput](t, call("run_command", map[string]any{
		"command": `id -u; for c in rg git node zsh gh; do command -v "$c" >/dev/null || exit 9; done`,
	}))
	if command.ExitCode != 0 || strings.TrimSpace(command.Stdout) == "0" {
		t.Fatalf("command: %#v", command)
	}
	outside := call("read_path", map[string]any{"path": "../etc/passwd"})
	if !outside.IsError {
		t.Fatalf("outside read succeeded: %#v", outside)
	}

	shell := exec.Command("docker", "run", "--init", "--rm", "-v", workspace+":/work", image, "zsh", "-lc", `test "$(id -u)" -ne 0; test -f /work/probe.txt; printf ok`)
	shellOutput, err := shell.CombinedOutput()
	if err != nil || !strings.HasSuffix(strings.TrimSpace(string(shellOutput)), "ok") {
		t.Fatalf("shell override: %v\n%s", err, shellOutput)
	}
}
