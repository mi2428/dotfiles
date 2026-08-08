package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func boolPtr(v bool) *bool { return &v }

func registerTools(server *mcp.Server, ws *workspace) {
	readOnly := &mcp.ToolAnnotations{
		ReadOnlyHint:    true,
		DestructiveHint: boolPtr(false),
		IdempotentHint:  true,
		OpenWorldHint:   boolPtr(false),
	}
	mutating := &mcp.ToolAnnotations{
		ReadOnlyHint:    false,
		DestructiveHint: boolPtr(true),
		IdempotentHint:  false,
		OpenWorldHint:   boolPtr(false),
	}

	mcp.AddTool(server, &mcp.Tool{
		Name:        "read_path",
		Title:       "Read path",
		Description: "Read a bounded file slice or directory listing inside /work.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, input readInput) (*mcp.CallToolResult, readOutput, error) {
		output, err := ws.readPath(input)
		return nil, output, err
	})

	mcp.AddTool(server, &mcp.Tool{
		Name:        "search_files",
		Title:       "Search files",
		Description: "Search text in workspace files using ripgrep.",
		Annotations: readOnly,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, input searchInput) (*mcp.CallToolResult, searchOutput, error) {
		output, err := ws.searchFiles(ctx, input)
		return nil, output, err
	})

	mcp.AddTool(server, &mcp.Tool{
		Name:        "apply_patch",
		Title:       "Apply patch",
		Description: "Apply a standard unified diff (`--- a/path` and `+++ b/path`) inside the workspace using git apply; custom patch envelopes are unsupported.",
		Annotations: mutating,
	}, func(ctx context.Context, _ *mcp.CallToolRequest, input patchInput) (*mcp.CallToolResult, patchOutput, error) {
		output, err := ws.applyPatch(ctx, input)
		return nil, output, err
	})

	mcp.AddTool(server, &mcp.Tool{
		Name:        "run_command",
		Title:       "Run command",
		Description: "Run a bounded shell command inside the workspace container.",
		Annotations: &mcp.ToolAnnotations{
			ReadOnlyHint:    false,
			DestructiveHint: boolPtr(true),
			IdempotentHint:  false,
			OpenWorldHint:   boolPtr(true),
		},
	}, func(ctx context.Context, _ *mcp.CallToolRequest, input commandInput) (*mcp.CallToolResult, commandOutput, error) {
		output, err := ws.runCommand(ctx, input)
		return nil, output, err
	})
}

func localOrigin(origin string) bool {
	if origin == "" {
		return true
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	switch u.Hostname() {
	case "localhost", "127.0.0.1", "::1":
		return true
	default:
		return false
	}
}

func newHandler(ws *workspace) http.Handler {
	server := mcp.NewServer(&mcp.Implementation{Name: "dotfiles-mcp-workspace", Version: "0.2.0"}, nil)
	registerTools(server, ws)
	mcpHandler := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server {
		return server
	}, &mcp.StreamableHTTPOptions{
		Stateless:                    true,
		JSONResponse:                 true,
		PropagateRequestCancellation: true,
		MaxRequestBodyBytes:          4 << 20,
	})

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_, _ = fmt.Fprintln(w, `{"ok":true}`)
	})
	mux.Handle("/mcp", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !localOrigin(r.Header.Get("Origin")) {
			http.Error(w, "invalid Origin", http.StatusForbidden)
			return
		}
		mcpHandler.ServeHTTP(w, r)
	}))
	return mux
}

func run(ctx context.Context, root, address string) error {
	ws, err := newWorkspace(root)
	if err != nil {
		return err
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return err
	}
	defer func() { _ = listener.Close() }()

	server := &http.Server{
		Handler:           newHandler(ws),
		ReadHeaderTimeout: 5 * time.Second,
	}
	errCh := make(chan error, 1)
	go func() {
		errCh <- server.Serve(listener)
	}()

	port := listener.Addr().(*net.TCPAddr).Port
	ready, _ := json.Marshal(map[string]any{
		"ok":   true,
		"port": port,
		"url":  "http://127.0.0.1:" + strconv.Itoa(port) + "/mcp",
	})
	fmt.Println(string(ready))

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}

func main() {
	root := os.Getenv("MCP_WORKSPACE_ROOT")
	if root == "" {
		root = "/work"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, root, net.JoinHostPort("0.0.0.0", port)); err != nil {
		log.Fatal(err)
	}
}
