package main

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

func TestChartMetadata(t *testing.T) {
	path, err := runfiles.Rlocation(mustEnv(t, "METADATA"))
	if err != nil {
		t.Fatalf("Failed to locate the metadata: %v", err)
	}

	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("Failed to read the metadata: %v", err)
	}

	var metadata struct {
		Name    string `json:"name"`
		Version string `json:"version"`
	}
	if err := json.Unmarshal(content, &metadata); err != nil {
		t.Fatalf("Failed to parse the metadata %s: %v", content, err)
	}

	if want := mustEnv(t, "EXPECTED_NAME"); metadata.Name != want {
		t.Errorf("chart name = %q, want %q", metadata.Name, want)
	}
	if want := mustEnv(t, "EXPECTED_VERSION"); metadata.Version != want {
		t.Errorf("chart version = %q, want %q", metadata.Version, want)
	}
}
