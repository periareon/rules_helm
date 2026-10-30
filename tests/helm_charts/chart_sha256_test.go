package main

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

func mustEnv(t *testing.T, key string) string {
	t.Helper()
	value := os.Getenv(key)
	if value == "" {
		t.Fatalf("%s is not set", key)
	}
	return value
}

func TestChartSha256(t *testing.T) {
	path, err := runfiles.Rlocation(mustEnv(t, "CHART"))
	if err != nil {
		t.Fatalf("Failed to locate the chart: %v", err)
	}

	file, err := os.Open(path)
	if err != nil {
		t.Fatalf("Failed to open the chart: %v", err)
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		t.Fatalf("Failed to read the chart: %v", err)
	}

	if got, want := hex.EncodeToString(hash.Sum(nil)), mustEnv(t, "EXPECTED_SHA256"); got != want {
		t.Errorf("chart sha256 = %s, want %s", got, want)
	}
}
