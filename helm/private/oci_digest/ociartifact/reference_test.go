package ociartifact

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRepository(t *testing.T) {
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
		got, err := Repository(tt.url, "demo")
		if err != nil {
			t.Errorf("Repository(%q) error: %v", tt.url, err)
			continue
		}
		if got != tt.want {
			t.Errorf("Repository(%q) = %q, want %q", tt.url, got, tt.want)
		}
	}
}

func TestRepositoryRejectsNonOCI(t *testing.T) {
	for _, url := range []string{"https://charts.example.com", "localhost:5051/charts", "oci://", "oci:///"} {
		if got, err := Repository(url, "demo"); err == nil {
			t.Errorf("Repository(%q) = %q, want an error", url, got)
		}
	}
}

func TestTag(t *testing.T) {
	for version, want := range map[string]string{
		"0.1.0":          "0.1.0",
		"0.1.0+build.1":  "0.1.0_build.1",
		"1.0.0-rc.1+a.b": "1.0.0-rc.1_a.b",
	} {
		if got := Tag(version); got != want {
			t.Errorf("Tag(%q) = %q, want %q", version, got, want)
		}
	}
}

func TestReadRegistryURL(t *testing.T) {
	file := filepath.Join(t.TempDir(), "url.txt")
	if err := os.WriteFile(file, []byte("  oci://localhost/charts\n"), 0644); err != nil {
		t.Fatal(err)
	}

	if got, err := ReadRegistryURL("", file); err != nil || got != "oci://localhost/charts" {
		t.Errorf("ReadRegistryURL from file = %q, %v", got, err)
	}
	if got, err := ReadRegistryURL("oci://localhost/charts", ""); err != nil || got != "oci://localhost/charts" {
		t.Errorf("ReadRegistryURL from value = %q, %v", got, err)
	}
	if _, err := ReadRegistryURL("", ""); err == nil {
		t.Error("ReadRegistryURL with neither set: want an error")
	}
	if _, err := ReadRegistryURL("oci://localhost/charts", file); err == nil {
		t.Error("ReadRegistryURL with both set: want an error")
	}

	empty := filepath.Join(t.TempDir(), "empty.txt")
	if err := os.WriteFile(empty, []byte(" \n"), 0644); err != nil {
		t.Fatal(err)
	}
	// The error quotes the path, which doubles Windows backslashes, so look for the base name.
	if _, err := ReadRegistryURL("", empty); err == nil || !strings.Contains(err.Error(), filepath.Base(empty)) {
		t.Errorf("ReadRegistryURL from an empty file: error = %v, want one naming the file", err)
	}
}
