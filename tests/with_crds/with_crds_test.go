package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
	"gopkg.in/yaml.v3"
)

type HelmChartDependency struct {
	Name       string
	Repository string
	Version    string
}

type HelmChart struct {
	Dependencies []HelmChartDependency
}

func loadChart(content string) (HelmChart, error) {
	var chart HelmChart
	err := yaml.Unmarshal([]byte(content), &chart)
	if err != nil {
		return chart, fmt.Errorf("Error unmarshalling chart content: %w", err)
	}

	return chart, nil
}

func TestWithCrdsTest(t *testing.T) {
	// Retrieve the Helm chart location from the environment variable
	helmChartPath := os.Getenv("HELM_CHART")
	if helmChartPath == "" {
		t.Fatal("HELM_CHART environment variable is not set")
	}

	// Locate the runfile
	path, err := runfiles.Rlocation(helmChartPath)
	if err != nil {
		t.Fatalf("Failed to find runfile with: %v", err)
	}

	// Open the .tgz file
	file, err := os.Open(path)
	if err != nil {
		t.Fatalf("Failed to open the Helm chart file: %v", err)
	}
	defer file.Close()

	// Wrap the file in a Gzip reader
	gzr, err := gzip.NewReader(file)
	if err != nil {
		t.Fatalf("Failed to create Gzip reader: %v", err)
	}
	defer gzr.Close()

	// Create a tar reader from the Gzip reader
	tarReader := tar.NewReader(gzr)

	// Initialize flags to check for the two files
	var crdsFound bool

	// Iterate through the tar archive
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break // End of archive
		}
		if err != nil {
			t.Fatalf("Error reading tar archive: %v", err)
		}

		if header.Name == "with-crds/crds/test.crd.yaml" {
			crdsFound = true
			if err != nil {
				t.Fatalf("Failed to read with-crds/crds/test.crd.yaml: %v", err)
			}
		}
	}

	if !crdsFound {
		t.Error("crds/test.crd.yaml was not found in the Helm chart")
	}
}
