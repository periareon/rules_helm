package ociartifact

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// writeChart writes a chart .tgz containing only `<name>/Chart.yaml`, plus a
// metadata.json with the given creation time, and returns their paths.
func writeChart(t *testing.T, name, chartYAML, created string) (string, string) {
	t.Helper()

	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	if err := tw.WriteHeader(&tar.Header{Name: name + "/Chart.yaml", Mode: 0644, Size: int64(len(chartYAML))}); err != nil {
		t.Fatal(err)
	}
	if _, err := tw.Write([]byte(chartYAML)); err != nil {
		t.Fatal(err)
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}

	dir := t.TempDir()
	chartPath := filepath.Join(dir, name+".tgz")
	if err := os.WriteFile(chartPath, buf.Bytes(), 0644); err != nil {
		t.Fatal(err)
	}
	return chartPath, writeMetadata(t, created)
}

func writeMetadata(t *testing.T, created string) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "metadata.json")
	if err := os.WriteFile(path, []byte(`{"created": "`+created+`"}`), 0644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadAnnotations(t *testing.T) {
	chartPath, metadataPath := writeChart(t, "demo", `apiVersion: v2
name: demo
version: 1.2.3
description: A demo chart
home: https://example.com
sources:
  - https://example.com/first
  - https://example.com/second
maintainers:
  - name: Alice
    email: alice@example.com
  - name: Bob
annotations:
  org.opencontainers.image.title: ignored
  org.opencontainers.image.version: ignored
  org.opencontainers.image.created: "2024-01-02T03:04:05Z"
  example.com/custom: value
`, "1970-01-01T00:00:00Z")

	artifact, err := Load(chartPath, metadataPath)
	if err != nil {
		t.Fatal(err)
	}

	want := map[string]string{
		"org.opencontainers.image.authors": "Alice (alice@example.com), Bob",
		// The chart's own annotation wins over the metadata's created time.
		"org.opencontainers.image.created":     "2024-01-02T03:04:05Z",
		"org.opencontainers.image.description": "A demo chart",
		"org.opencontainers.image.source":      "https://example.com/first",
		"org.opencontainers.image.title":       "demo",
		"org.opencontainers.image.url":         "https://example.com",
		"org.opencontainers.image.version":     "1.2.3",
		"example.com/custom":                   "value",
	}
	if !reflect.DeepEqual(artifact.Annotations, want) {
		t.Errorf("Annotations = %v, want %v", artifact.Annotations, want)
	}
}

func TestLoadConfigBlob(t *testing.T) {
	chartPath, metadataPath := writeChart(t, "demo", "name: demo\nversion: 1.2.3\ndescription: \"tab\\there\"\n", "1970-01-01T00:00:00Z")

	artifact, err := Load(chartPath, metadataPath)
	if err != nil {
		t.Fatal(err)
	}

	// Helm defaults apiVersion to v1 and replaces whitespace control characters.
	want := `{"name":"demo","version":"1.2.3","description":"tab here","apiVersion":"v1"}`
	if got := string(artifact.ConfigBlob); got != want {
		t.Errorf("ConfigBlob = %s, want %s", got, want)
	}
}

func TestLoadRequiresCreated(t *testing.T) {
	chartPath, _ := writeChart(t, "demo", "name: demo\nversion: 1.2.3\n", "")
	metadataPath := filepath.Join(t.TempDir(), "metadata.json")
	if err := os.WriteFile(metadataPath, []byte(`{}`), 0644); err != nil {
		t.Fatal(err)
	}

	if _, err := Load(chartPath, metadataPath); err == nil || !strings.Contains(err.Error(), "created") {
		t.Errorf("Load() error = %v, want a missing `created` error", err)
	}
}
