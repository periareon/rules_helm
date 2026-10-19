package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"text/template"
)

func TestDestination(t *testing.T) {
	tests := []struct {
		url  string
		want string
	}{
		{"oci://localhost:5051/charts", "localhost:5051/charts/demo"},
		{"oci://localhost:5051/charts/", "localhost:5051/charts/demo"},
		{"oci://localhost:5051", "localhost:5051/demo"},
		{"oci://registry.example.com/a/b", "registry.example.com/a/b/demo"},
		{"oci://localhost:5051//charts", "localhost:5051/charts/demo"},
		{"oci://localhost:5051/charts//", "localhost:5051/charts/demo"},
	}
	for _, tt := range tests {
		got, err := destination(tt.url, "demo")
		if err != nil {
			t.Errorf("destination(%q) error: %v", tt.url, err)
			continue
		}
		if got != tt.want {
			t.Errorf("destination(%q) = %q, want %q", tt.url, got, tt.want)
		}
	}
}

func TestDestinationRejectsNonOCI(t *testing.T) {
	for _, url := range []string{"https://charts.example.com", "localhost:5051/charts", "oci://", "oci:///"} {
		if got, err := destination(url, "demo"); err == nil {
			t.Errorf("destination(%q) = %q, want an error", url, got)
		}
	}
}

func TestTag(t *testing.T) {
	for version, want := range map[string]string{
		"0.1.0":          "0.1.0",
		"0.1.0+build.1":  "0.1.0_build.1",
		"1.0.0-rc.1+a.b": "1.0.0-rc.1_a.b",
	} {
		if got := tag(version); got != want {
			t.Errorf("tag(%q) = %q, want %q", version, got, want)
		}
	}
}

// TestEscapeTemplate expands escaped values the way `rules_img` does and
// expects the original back.
func TestEscapeTemplate(t *testing.T) {
	for _, value := range []string{
		"",
		"plain",
		"{{",
		"}}",
		"{{ .Values.x }}",
		"{{{",
		"{{-",
		`{{"{{"}}`,
		"a {{ b }} c {{",
	} {
		tmpl, err := template.New("expand").Parse(escapeTemplate(value))
		if err != nil {
			t.Errorf("parsing escapeTemplate(%q): %v", value, err)
			continue
		}
		var buf bytes.Buffer
		if err := tmpl.Execute(&buf, map[string]any{}); err != nil {
			t.Errorf("executing escapeTemplate(%q): %v", value, err)
			continue
		}
		if got := buf.String(); got != value {
			t.Errorf("expanding escapeTemplate(%q) = %q", value, got)
		}
	}
}

func TestReadRegistryURL(t *testing.T) {
	file := filepath.Join(t.TempDir(), "url.txt")
	if err := os.WriteFile(file, []byte("  oci://localhost/charts\n"), 0644); err != nil {
		t.Fatal(err)
	}

	if got, err := readRegistryURL("", file); err != nil || got != "oci://localhost/charts" {
		t.Errorf("readRegistryURL from file = %q, %v", got, err)
	}
	if got, err := readRegistryURL("oci://localhost/charts", ""); err != nil || got != "oci://localhost/charts" {
		t.Errorf("readRegistryURL from value = %q, %v", got, err)
	}
	if _, err := readRegistryURL("", ""); err == nil {
		t.Error("readRegistryURL with neither set: want an error")
	}
	if _, err := readRegistryURL("oci://localhost/charts", file); err == nil {
		t.Error("readRegistryURL with both set: want an error")
	}

	empty := filepath.Join(t.TempDir(), "empty.txt")
	if err := os.WriteFile(empty, []byte(" \n"), 0644); err != nil {
		t.Fatal(err)
	}
	// The error quotes the path, which doubles Windows backslashes, so look for the base name.
	if _, err := readRegistryURL("", empty); err == nil || !strings.Contains(err.Error(), filepath.Base(empty)) {
		t.Errorf("readRegistryURL from an empty file: error = %v, want one naming the file", err)
	}
}
