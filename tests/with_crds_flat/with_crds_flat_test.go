package main

import (
	"archive/tar"
	"compress/gzip"
	"io"
	"os"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

// TestWithCrdsFlatTest verifies the packager handles a CRD input whose Bazel
// shortpath contains no `crds/` ancestor. Helm requires CRDs to live under the
// chart's `crds/` directory, so the packager must still stage `my_crd.yaml`
// at `<chart>/crds/my_crd.yaml`.
//
// Pre-fix, the packager's CRDs root-finding loop walked the shortpath upward
// looking for a `crds/` ancestor and only terminated when `len(current) == 0`.
// Because `filepath.Dir(".") == "."`, that condition was never reached and
// the packager hung indefinitely at 100% CPU. This test would time out under
// the unfixed packager.
func TestWithCrdsFlatTest(t *testing.T) {
	helmChartPath := os.Getenv("HELM_CHART")
	if helmChartPath == "" {
		t.Fatal("HELM_CHART environment variable is not set")
	}

	path, err := runfiles.Rlocation(helmChartPath)
	if err != nil {
		t.Fatalf("Failed to find runfile: %v", err)
	}

	file, err := os.Open(path)
	if err != nil {
		t.Fatalf("Failed to open the Helm chart file: %v", err)
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		t.Fatalf("Failed to create Gzip reader: %v", err)
	}
	defer gzr.Close()

	tarReader := tar.NewReader(gzr)

	const wantCRDPath = "with-crds-flat/crds/my_crd.yaml"
	var crdFound bool

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("Error reading tar archive: %v", err)
		}

		if header.Name == wantCRDPath {
			crdFound = true
		}
	}

	if !crdFound {
		t.Errorf("expected %q in the packaged chart, but it was not present", wantCRDPath)
	}
}
