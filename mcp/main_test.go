package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func testWorkspace(t *testing.T) *workspace {
	t.Helper()
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "nested"), 0o755); err != nil {
		t.Fatal(err)
	}
	for path, content := range map[string]string{
		"README.md":         "alpha\nbeta\ngamma\n",
		"nested/needle.txt": "needle\n",
		"nested/other.txt":  "other\n",
	} {
		if err := os.WriteFile(filepath.Join(root, path), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	ws, err := newWorkspace(root)
	if err != nil {
		t.Fatal(err)
	}
	return ws
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, output)
	}
}

func TestWorkspaceBoundary(t *testing.T) {
	ws := testWorkspace(t)
	outside := t.TempDir()
	secret := filepath.Join(outside, "secret.txt")
	if err := os.WriteFile(secret, []byte("nope"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(secret, filepath.Join(ws.root, "nested", "escape.txt")); err != nil {
		t.Fatal(err)
	}
	if _, err := ws.resolve(filepath.Join("..", filepath.Base(outside), "secret.txt"), false); err == nil || !strings.Contains(err.Error(), "escapes workspace") {
		t.Fatalf("traversal was not rejected: %v", err)
	}
	if _, err := ws.resolve("nested/escape.txt", false); err == nil || !strings.Contains(err.Error(), "escapes workspace") {
		t.Fatalf("symlink escape was not rejected: %v", err)
	}
}

func TestWorkspaceTools(t *testing.T) {
	ws := testWorkspace(t)
	runGit(t, ws.root, "init", "-q")

	directory, err := ws.readPath(readInput{Path: "."})
	if err != nil || directory.Kind != "directory" || directory.Truncated {
		t.Fatalf("read directory: %#v, %v", directory, err)
	}
	file, err := ws.readPath(readInput{Path: "README.md", StartLine: 2, MaxLines: 1})
	if err != nil || file.Text != "2: beta" || file.EndLine != 2 || !file.Truncated {
		t.Fatalf("read file: %#v, %v", file, err)
	}
	if err := os.WriteFile(filepath.Join(ws.root, "long.txt"), []byte(strings.Repeat("界", 100)), 0o644); err != nil {
		t.Fatal(err)
	}
	long, err := ws.readPath(readInput{Path: "long.txt", MaxBytes: 32})
	if err != nil || len([]byte(long.Text)) > 32 || !long.Truncated {
		t.Fatalf("bounded read: %#v, %v", long, err)
	}

	search, err := ws.searchFiles(context.Background(), searchInput{Query: "needle"})
	if err != nil || len(search.Matches) != 1 || search.Matches[0].Path != "nested/needle.txt" {
		t.Fatalf("search: %#v, %v", search, err)
	}

	patch := "--- a/README.md\n+++ b/README.md\n@@ -1,3 +1,3 @@\n alpha\n-beta\n+patched\n gamma\n"
	applied, err := ws.applyPatch(context.Background(), patchInput{Patch: patch})
	if err != nil || !applied.Applied {
		t.Fatalf("patch: %#v, %v", applied, err)
	}
	contents, err := os.ReadFile(filepath.Join(ws.root, "README.md"))
	if err != nil || !strings.Contains(string(contents), "patched") {
		t.Fatalf("patched file: %s, %v", contents, err)
	}

	t.Setenv("TEST_SECRET", "supersecret")
	command, err := ws.runCommand(context.Background(), commandInput{
		Command:        `printf super; sleep 0.01; printf secret; printf stderr >&2`,
		TimeoutMS:      2000,
		MaxOutputBytes: 1024,
	})
	if err != nil || command.ExitCode != 0 || command.Stdout != "[redacted]" || command.Stderr != "stderr" {
		t.Fatalf("command: %#v, %v", command, err)
	}
	failure, err := ws.runCommand(context.Background(), commandInput{Command: "exit 7", TimeoutMS: 2000})
	if err != nil || failure.ExitCode != 7 {
		t.Fatalf("failure: %#v, %v", failure, err)
	}
	timed, err := ws.runCommand(context.Background(), commandInput{Command: "sleep 2", TimeoutMS: 50})
	if err != nil || !timed.TimedOut {
		t.Fatalf("timeout: %#v, %v", timed, err)
	}
	loud, err := ws.runCommand(context.Background(), commandInput{
		Command:        `i=0; while [ "$i" -lt 5000 ]; do printf x; i=$((i + 1)); done`,
		TimeoutMS:      2000,
		MaxOutputBytes: 1024,
	})
	if err != nil || !loud.Truncated || len([]byte(loud.Stdout))+len([]byte(loud.Stderr)) > 1024 {
		t.Fatalf("output cap: %#v, %v", loud, err)
	}
}

func decodeStructured[T any](t *testing.T, result *mcp.CallToolResult) T {
	t.Helper()
	data, err := json.Marshal(result.StructuredContent)
	if err != nil {
		t.Fatal(err)
	}
	var output T
	if err := json.Unmarshal(data, &output); err != nil {
		t.Fatal(err)
	}
	return output
}

func TestStreamableHTTP(t *testing.T) {
	ws := testWorkspace(t)
	runGit(t, ws.root, "init", "-q")
	server := httptest.NewServer(newHandler(ws))
	t.Cleanup(server.Close)

	response, err := http.Get(server.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = response.Body.Close() })
	if response.StatusCode != http.StatusOK {
		t.Fatalf("health status: %d", response.StatusCode)
	}
	var health map[string]bool
	if err := json.NewDecoder(response.Body).Decode(&health); err != nil || !health["ok"] {
		t.Fatalf("health body: %#v, %v", health, err)
	}

	client := mcp.NewClient(&mcp.Implementation{Name: "test", Version: "0"}, nil)
	session, err := client.Connect(context.Background(), &mcp.StreamableClientTransport{Endpoint: server.URL + "/mcp"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = session.Close() })
	tools, err := session.ListTools(context.Background(), nil)
	if err != nil || len(tools.Tools) != 4 {
		t.Fatalf("tools: %#v, %v", tools, err)
	}
	result, err := session.CallTool(context.Background(), &mcp.CallToolParams{
		Name:      "read_path",
		Arguments: map[string]any{"path": "README.md"},
	})
	if err != nil || result.IsError {
		t.Fatalf("read tool: %#v, %v", result, err)
	}
	read := decodeStructured[readOutput](t, result)
	if !strings.Contains(read.Text, "alpha") {
		t.Fatalf("read output: %#v", read)
	}

	request, err := http.NewRequest(http.MethodPost, server.URL+"/mcp", strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}`))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Origin", "http://evil.example")
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json, text/event-stream")
	blocked, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	_ = blocked.Body.Close()
	if blocked.StatusCode != http.StatusForbidden {
		t.Fatalf("origin status: %d", blocked.StatusCode)
	}
}

func TestRunStopsOnContextCancellation(t *testing.T) {
	ws := testWorkspace(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := ws.runCommand(ctx, commandInput{Command: "sleep 2", TimeoutMS: int((2 * time.Second).Milliseconds())})
	if err == nil {
		t.Fatal("expected cancellation")
	}
}
