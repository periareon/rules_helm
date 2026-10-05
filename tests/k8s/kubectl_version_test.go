package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

type versionOutput struct {
	ClientVersion struct {
		GitVersion string `json:"gitVersion"`
	} `json:"clientVersion"`
}

func mustEnv(t *testing.T, key string) string {
	t.Helper()
	value := os.Getenv(key)
	if value == "" {
		t.Fatalf("%s is not set", key)
	}
	return value
}

func mustRlocation(t *testing.T, rlocationpath string) string {
	t.Helper()
	path, err := runfiles.Rlocation(rlocationpath)
	if err != nil {
		t.Fatalf("Failed to locate runfile %s: %v", rlocationpath, err)
	}
	return path
}

// versionJSON returns the output of `kubectl version --client --output json`.
//
// When `KUBECTL_VERSION_JSON` is set it names a runfile that already contains
// that output (produced by a genrule); otherwise `KUBECTL` names the binary to
// run.
func versionJSON(t *testing.T) []byte {
	t.Helper()

	if rlocationpath := os.Getenv("KUBECTL_VERSION_JSON"); rlocationpath != "" {
		raw, err := os.ReadFile(mustRlocation(t, rlocationpath))
		if err != nil {
			t.Fatalf("Failed to read %s: %v", rlocationpath, err)
		}
		return raw
	}

	kubectl := mustRlocation(t, mustEnv(t, "KUBECTL"))

	cmd := exec.Command(kubectl, "version", "--client", "--output", "json")
	// Keep the test independent of any kubeconfig on the host.
	cmd.Env = append(os.Environ(), fmt.Sprintf("HOME=%s", t.TempDir()), "KUBECONFIG=")
	cmd.Stderr = os.Stderr

	raw, err := cmd.Output()
	if err != nil {
		t.Fatalf("`%s version --client` failed: %v", kubectl, err)
	}
	return raw
}

func TestKubectlVersion(t *testing.T) {
	expected := mustEnv(t, "EXPECTED_VERSION")
	raw := versionJSON(t)

	var parsed versionOutput
	if err := json.Unmarshal(raw, &parsed); err != nil {
		t.Fatalf("Failed to parse kubectl version output %q: %v", raw, err)
	}

	if parsed.ClientVersion.GitVersion != expected {
		t.Fatalf("Expected kubectl %s, got %s (output: %s)", expected, parsed.ClientVersion.GitVersion, raw)
	}
}
