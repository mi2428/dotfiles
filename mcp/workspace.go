package main

import (
	"bufio"
	"bytes"
	"context"
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
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unicode/utf8"
)

const (
	defaultOutputBytes = 64 << 10
	maxReadableBytes   = 8 << 20
)

var secretName = regexp.MustCompile(`(?i)(TOKEN|SECRET|PASSWORD|KEY)$`)

type workspace struct {
	root string
}

type readInput struct {
	Path       string `json:"path" jsonschema:"path relative to the workspace root"`
	StartLine  int    `json:"startLine,omitempty" jsonschema:"first line to return; defaults to 1"`
	MaxLines   int    `json:"maxLines,omitempty" jsonschema:"maximum lines to return; capped at 4000"`
	MaxEntries int    `json:"maxEntries,omitempty" jsonschema:"maximum directory entries to return; capped at 2000"`
	MaxBytes   int    `json:"maxBytes,omitempty" jsonschema:"maximum text bytes to return; capped at 262144"`
}

type pathEntry struct {
	Name string `json:"name"`
	Kind string `json:"kind"`
}

type readOutput struct {
	Kind      string      `json:"kind"`
	Path      string      `json:"path"`
	Entries   []pathEntry `json:"entries,omitempty"`
	StartLine int         `json:"startLine,omitempty"`
	EndLine   int         `json:"endLine,omitempty"`
	Text      string      `json:"text,omitempty"`
	Truncated bool        `json:"truncated"`
}

type searchInput struct {
	Query          string `json:"query" jsonschema:"regular expression to search for"`
	Glob           string `json:"glob,omitempty" jsonschema:"optional ripgrep glob"`
	Limit          int    `json:"limit,omitempty" jsonschema:"maximum matches to return; capped at 500"`
	TimeoutMS      int    `json:"timeoutMs,omitempty" jsonschema:"timeout in milliseconds; capped at 300000"`
	MaxOutputBytes int    `json:"maxOutputBytes,omitempty" jsonschema:"maximum output bytes; capped at 1048576"`
}

type searchMatch struct {
	Path       string `json:"path"`
	LineNumber int    `json:"lineNumber"`
	Text       string `json:"text"`
}

type searchOutput struct {
	Kind      string        `json:"kind"`
	Query     string        `json:"query"`
	Glob      string        `json:"glob,omitempty"`
	Matches   []searchMatch `json:"matches"`
	Truncated bool          `json:"truncated"`
	TimedOut  bool          `json:"timedOut"`
}

type patchInput struct {
	Patch string `json:"patch" jsonschema:"standard unified diff to apply"`
}

type patchOutput struct {
	Kind    string `json:"kind"`
	Applied bool   `json:"applied"`
}

type commandInput struct {
	Command        string `json:"command" jsonschema:"shell command to run"`
	CWD            string `json:"cwd,omitempty" jsonschema:"working directory relative to the workspace root"`
	TimeoutMS      int    `json:"timeoutMs,omitempty" jsonschema:"timeout in milliseconds; capped at 300000"`
	MaxOutputBytes int    `json:"maxOutputBytes,omitempty" jsonschema:"maximum output bytes; capped at 1048576"`
}

type commandOutput struct {
	Kind       string `json:"kind"`
	Command    string `json:"command"`
	CWD        string `json:"cwd"`
	ExitCode   int    `json:"exitCode"`
	Signal     string `json:"signal,omitempty"`
	TimedOut   bool   `json:"timedOut"`
	Truncated  bool   `json:"truncated"`
	DurationMS int64  `json:"durationMs"`
	Stdout     string `json:"stdout"`
	Stderr     string `json:"stderr"`
}

func newWorkspace(root string) (*workspace, error) {
	realRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(realRoot)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("workspace root is not a directory: %s", root)
	}
	absRoot, err := filepath.Abs(realRoot)
	if err != nil {
		return nil, err
	}
	return &workspace{root: filepath.Clean(absRoot)}, nil
}

func inside(root, candidate string) bool {
	rel, err := filepath.Rel(root, candidate)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel)
}

func (w *workspace) resolve(path string, allowMissing bool) (string, error) {
	if path == "" {
		path = "."
	}
	candidate := path
	if !filepath.IsAbs(candidate) {
		candidate = filepath.Join(w.root, candidate)
	}
	candidate = filepath.Clean(candidate)
	realPath, err := filepath.EvalSymlinks(candidate)
	if err == nil {
		if !inside(w.root, realPath) {
			return "", fmt.Errorf("path escapes workspace: %s", path)
		}
		return realPath, nil
	}
	if !allowMissing || !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	ancestor := filepath.Dir(candidate)
	for {
		realAncestor, ancestorErr := filepath.EvalSymlinks(ancestor)
		if ancestorErr == nil {
			if !inside(w.root, realAncestor) {
				return "", fmt.Errorf("path escapes workspace: %s", path)
			}
			remainder, relErr := filepath.Rel(ancestor, candidate)
			if relErr != nil {
				return "", relErr
			}
			return filepath.Join(realAncestor, remainder), nil
		}
		parent := filepath.Dir(ancestor)
		if !errors.Is(ancestorErr, os.ErrNotExist) || parent == ancestor {
			return "", ancestorErr
		}
		ancestor = parent
	}
}

func (w *workspace) relative(path string) string {
	rel, err := filepath.Rel(w.root, path)
	if err != nil || rel == "" {
		return "."
	}
	return filepath.ToSlash(rel)
}

func defaults(value, fallback, maximum int) int {
	if value <= 0 {
		return fallback
	}
	if value > maximum {
		return maximum
	}
	return value
}

func utf8Slice(text string, maxBytes int) string {
	data := []byte(text)
	if len(data) <= maxBytes {
		return text
	}
	data = data[:maxBytes]
	for len(data) > 0 && !utf8.Valid(data) {
		data = data[:len(data)-1]
	}
	return string(data)
}

func (w *workspace) readPath(input readInput) (readOutput, error) {
	target, err := w.resolve(input.Path, false)
	if err != nil {
		return readOutput{}, err
	}
	info, err := os.Stat(target)
	if err != nil {
		return readOutput{}, err
	}
	if info.IsDir() {
		limit := defaults(input.MaxEntries, 200, 2000)
		dir, err := os.Open(target)
		if err != nil {
			return readOutput{}, err
		}
		defer func() { _ = dir.Close() }()
		entries, err := dir.ReadDir(limit + 1)
		if err != nil && !errors.Is(err, io.EOF) {
			return readOutput{}, err
		}
		truncated := len(entries) > limit
		if truncated {
			entries = entries[:limit]
		}
		output := make([]pathEntry, 0, len(entries))
		for _, entry := range entries {
			kind := "file"
			if entry.IsDir() {
				kind = "directory"
			} else if entry.Type()&os.ModeSymlink != 0 {
				kind = "symlink"
			}
			output = append(output, pathEntry{Name: entry.Name(), Kind: kind})
		}
		sort.Slice(output, func(i, j int) bool { return output[i].Name < output[j].Name })
		return readOutput{Kind: "directory", Path: w.relative(target), Entries: output, Truncated: truncated}, nil
	}
	if info.Size() > maxReadableBytes {
		return readOutput{}, fmt.Errorf("file is too large to read: %s", input.Path)
	}
	data, err := os.ReadFile(target)
	if err != nil {
		return readOutput{}, err
	}
	text := strings.ReplaceAll(string(data), "\r\n", "\n")
	lines := strings.Split(text, "\n")
	start := defaults(input.StartLine, 1, int(^uint(0)>>1))
	lineLimit := defaults(input.MaxLines, 200, 4000)
	from := min(start-1, len(lines))
	to := min(from+lineLimit, len(lines))
	var builder strings.Builder
	for index, line := range lines[from:to] {
		fmt.Fprintf(&builder, "%d: %s", start+index, line)
		if index < to-from-1 {
			builder.WriteByte('\n')
		}
	}
	maxBytes := defaults(input.MaxBytes, defaultOutputBytes, 256<<10)
	preview := builder.String()
	return readOutput{
		Kind:      "file",
		Path:      w.relative(target),
		StartLine: start,
		EndLine:   start + to - from - 1,
		Text:      utf8Slice(preview, maxBytes),
		Truncated: to < len(lines) || len([]byte(preview)) > maxBytes,
	}, nil
}

type processOptions struct {
	dir            string
	env            []string
	stdin          []byte
	timeout        time.Duration
	maxOutputBytes int
}

type processResult struct {
	exitCode  int
	signal    string
	stdout    string
	stderr    string
	timedOut  bool
	truncated bool
}

type capturedStreams struct {
	mu        sync.Mutex
	stdout    bytes.Buffer
	stderr    bytes.Buffer
	limit     int
	truncated bool
	stop      func()
}

type streamWriter struct {
	capture *capturedStreams
	stderr  bool
}

func (w streamWriter) Write(data []byte) (int, error) {
	c := w.capture
	c.mu.Lock()
	room := c.limit - c.stdout.Len() - c.stderr.Len()
	written := min(room, len(data))
	if written > 0 {
		if w.stderr {
			_, _ = c.stderr.Write(data[:written])
		} else {
			_, _ = c.stdout.Write(data[:written])
		}
	}
	overflow := written < len(data)
	if overflow {
		c.truncated = true
	}
	stop := c.stop
	c.mu.Unlock()
	if overflow && stop != nil {
		stop()
	}
	return len(data), nil
}

func envSecrets(env []string) []string {
	var secrets []string
	for _, item := range env {
		name, value, ok := strings.Cut(item, "=")
		if ok && len(value) > 6 && secretName.MatchString(name) {
			secrets = append(secrets, value)
		}
	}
	sort.Slice(secrets, func(i, j int) bool { return len(secrets[i]) > len(secrets[j]) })
	return secrets
}

func redact(text string, secrets []string) string {
	for _, secret := range secrets {
		text = strings.ReplaceAll(text, secret, "[redacted]")
	}
	return text
}

func signalGroup(cmd *exec.Cmd, signal syscall.Signal) {
	if cmd.Process == nil {
		return
	}
	if err := syscall.Kill(-cmd.Process.Pid, signal); err != nil {
		_ = cmd.Process.Signal(signal)
	}
}

func runProcess(ctx context.Context, name string, args []string, options processOptions) (processResult, error) {
	if options.timeout <= 0 {
		options.timeout = 30 * time.Second
	}
	if options.maxOutputBytes <= 0 {
		options.maxOutputBytes = defaultOutputBytes
	}
	if options.env == nil {
		options.env = os.Environ()
	}
	secrets := envSecrets(options.env)
	extra := 0
	for _, secret := range secrets {
		extra = max(extra, len([]byte(secret)))
	}

	cmd := exec.Command(name, args...)
	cmd.Dir = options.dir
	cmd.Env = options.env
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if options.stdin != nil {
		cmd.Stdin = bytes.NewReader(options.stdin)
	}
	capture := &capturedStreams{limit: options.maxOutputBytes + extra}
	cmd.Stdout = streamWriter{capture: capture}
	cmd.Stderr = streamWriter{capture: capture, stderr: true}

	var finished atomic.Bool
	done := make(chan struct{})
	var stopOnce sync.Once
	stopProcess := func() {
		if finished.Load() {
			return
		}
		stopOnce.Do(func() {
			signalGroup(cmd, syscall.SIGTERM)
			go func() {
				select {
				case <-done:
				case <-time.After(time.Second):
					if !finished.Load() {
						signalGroup(cmd, syscall.SIGKILL)
					}
				}
			}()
		})
	}
	capture.stop = stopProcess

	if err := cmd.Start(); err != nil {
		return processResult{}, err
	}
	var timedOut atomic.Bool
	timer := time.AfterFunc(options.timeout, func() {
		timedOut.Store(true)
		stopProcess()
	})
	go func() {
		select {
		case <-ctx.Done():
			stopProcess()
		case <-done:
		}
	}()
	waitErr := cmd.Wait()
	finished.Store(true)
	close(done)
	timer.Stop()
	if ctx.Err() != nil && !timedOut.Load() {
		return processResult{}, ctx.Err()
	}
	var exitError *exec.ExitError
	if waitErr != nil && !errors.As(waitErr, &exitError) {
		return processResult{}, waitErr
	}

	capture.mu.Lock()
	stdout := redact(capture.stdout.String(), secrets)
	stderr := redact(capture.stderr.String(), secrets)
	truncated := capture.truncated
	capture.mu.Unlock()
	stdoutCap := utf8Slice(stdout, options.maxOutputBytes)
	stderrCap := utf8Slice(stderr, max(0, options.maxOutputBytes-len([]byte(stdoutCap))))
	if stdoutCap != stdout || stderrCap != stderr {
		truncated = true
	}
	result := processResult{
		exitCode:  cmd.ProcessState.ExitCode(),
		stdout:    stdoutCap,
		stderr:    stderrCap,
		timedOut:  timedOut.Load(),
		truncated: truncated,
	}
	if status, ok := cmd.ProcessState.Sys().(syscall.WaitStatus); ok && status.Signaled() {
		result.signal = status.Signal().String()
	}
	return result, nil
}

func (w *workspace) searchFiles(ctx context.Context, input searchInput) (searchOutput, error) {
	if input.Query == "" {
		return searchOutput{}, errors.New("query is required")
	}
	limit := defaults(input.Limit, 50, 500)
	args := []string{"-n", "--hidden", "--color", "never", "--max-count", strconv.Itoa(limit)}
	if input.Glob != "" {
		args = append(args, "--glob", input.Glob)
	}
	args = append(args, input.Query)
	result, err := runProcess(ctx, "rg", args, processOptions{
		dir:            w.root,
		timeout:        time.Duration(defaults(input.TimeoutMS, 5000, 300000)) * time.Millisecond,
		maxOutputBytes: defaults(input.MaxOutputBytes, defaultOutputBytes, 1<<20),
	})
	if err != nil {
		return searchOutput{}, err
	}
	if result.exitCode > 1 && !result.timedOut && !result.truncated {
		return searchOutput{}, fmt.Errorf("rg failed: %s", result.stderr)
	}
	var matches []searchMatch
	for line := range strings.SplitSeq(strings.TrimSpace(result.stdout), "\n") {
		if line == "" {
			continue
		}
		parts := strings.SplitN(line, ":", 3)
		if len(parts) != 3 {
			continue
		}
		lineNumber, err := strconv.Atoi(parts[1])
		if err != nil {
			continue
		}
		matches = append(matches, searchMatch{Path: filepath.ToSlash(parts[0]), LineNumber: lineNumber, Text: parts[2]})
	}
	truncated := result.truncated || len(matches) > limit
	if len(matches) > limit {
		matches = matches[:limit]
	}
	return searchOutput{Kind: "search", Query: input.Query, Glob: input.Glob, Matches: matches, Truncated: truncated, TimedOut: result.timedOut}, nil
}

func (w *workspace) validatePatchPaths(patch string) error {
	scanner := bufio.NewScanner(strings.NewReader(patch))
	scanner.Buffer(make([]byte, 64<<10), 1<<20)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "--- ") && !strings.HasPrefix(line, "+++ ") {
			continue
		}
		path := strings.TrimSpace(line[4:])
		path, _, _ = strings.Cut(path, "\t")
		if path == "/dev/null" {
			continue
		}
		path = strings.TrimPrefix(strings.TrimPrefix(path, "a/"), "b/")
		if _, err := w.resolve(path, true); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func (w *workspace) applyPatch(ctx context.Context, input patchInput) (patchOutput, error) {
	if input.Patch == "" {
		return patchOutput{}, errors.New("patch is required")
	}
	if err := w.validatePatchPaths(input.Patch); err != nil {
		return patchOutput{}, err
	}
	options := processOptions{dir: w.root, stdin: []byte(input.Patch), timeout: 5 * time.Second, maxOutputBytes: defaultOutputBytes}
	check, err := runProcess(ctx, "git", []string{"apply", "--check", "--whitespace=nowarn", "-"}, options)
	if err != nil {
		return patchOutput{}, err
	}
	if check.exitCode != 0 {
		return patchOutput{}, fmt.Errorf("git apply --check failed: %s", check.stderr)
	}
	applied, err := runProcess(ctx, "git", []string{"apply", "--whitespace=nowarn", "-"}, options)
	if err != nil {
		return patchOutput{}, err
	}
	if applied.exitCode != 0 {
		return patchOutput{}, fmt.Errorf("git apply failed: %s", applied.stderr)
	}
	return patchOutput{Kind: "patch", Applied: true}, nil
}

func (w *workspace) runCommand(ctx context.Context, input commandInput) (commandOutput, error) {
	if input.Command == "" {
		return commandOutput{}, errors.New("command is required")
	}
	dir, err := w.resolve(input.CWD, false)
	if err != nil {
		return commandOutput{}, err
	}
	started := time.Now()
	result, err := runProcess(ctx, "/bin/sh", []string{"-c", input.Command}, processOptions{
		dir:            dir,
		timeout:        time.Duration(defaults(input.TimeoutMS, 30000, 300000)) * time.Millisecond,
		maxOutputBytes: defaults(input.MaxOutputBytes, defaultOutputBytes, 1<<20),
	})
	if err != nil {
		return commandOutput{}, err
	}
	return commandOutput{
		Kind:       "command",
		Command:    redact(input.Command, envSecrets(os.Environ())),
		CWD:        w.relative(dir),
		ExitCode:   result.exitCode,
		Signal:     result.signal,
		TimedOut:   result.timedOut,
		Truncated:  result.truncated,
		DurationMS: time.Since(started).Milliseconds(),
		Stdout:     result.stdout,
		Stderr:     result.stderr,
	}, nil
}
