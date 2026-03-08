package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"strings"
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

func TestWithChartDepsTest(t *testing.T) {
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
	var grafanaChartFound, redisChartFound, postgresChartFound bool
	var chartContent, grafanaChartContent, redisChartContent, postgresChartContent string

	// Iterate through the tar archive
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break // End of archive
		}
		if err != nil {
			t.Fatalf("Error reading tar archive: %v", err)
		}
		// Read the Chart.yaml content so that we can check its content
		if header.Name == "with-external-deps/Chart.yaml" {
			content, err := io.ReadAll(tarReader)
			if err != nil {
				t.Fatalf("Failed to read Chart.yaml: %v", err)
			}
			chartContent = string(content)
		}

		// Check for the three specific files
		if header.Name == "with-external-deps/charts/grafana/Chart.yaml" {
			grafanaChartFound = true
			content, err := io.ReadAll(tarReader)
			if err != nil {
				t.Fatalf("Failed to read grafana Chart.yaml: %v", err)
			}
			grafanaChartContent = string(content)
		}

		if header.Name == "with-external-deps/charts/redis/Chart.yaml" {
			redisChartFound = true
			content, err := io.ReadAll(tarReader)
			if err != nil {
				t.Fatalf("Failed to read redis Chart.yaml: %v", err)
			}
			redisChartContent = string(content)
		}

		if header.Name == "with-external-deps/charts/postgresql/Chart.yaml" {
			postgresChartFound = true
			content, err := io.ReadAll(tarReader)
			if err != nil {
				t.Fatalf("Failed to read postgresql Chart.yaml: %v", err)
			}
			postgresChartContent = string(content)
		}
	}

	// Assert that all files were found
	// Assert that dependencie were found
	if !grafanaChartFound {
		t.Error("charts/grafana/Chart.yaml was not found in the Helm chart")
	}
	if !redisChartFound {
		t.Error("charts/redis/Chart.yaml was not found in the Helm chart")
	}
	if !postgresChartFound {
		t.Error("charts/postgresql/Chart.yaml was not found in the Helm chart")
	}

	// Assert that the the main Chart.yaml contains the expected dependencies
	chart, err := loadChart(chartContent)
	if err != nil {
		t.Fatalf("Failed to load main Chart.yaml: %v", err)
	}
	if len(chart.Dependencies) != 6 {
		t.Fatalf("Expected 6 dependencies in main Chart.yaml, but found %d", len(chart.Dependencies))
	}

	expectedDeps := map[string]HelmChartDependency{
		"dep1":       		{Name: "dep1", Repository: "", Version: "0.1.0"},
		"dep2":       		{Name: "dep2", Repository: "", Version: "0.1.0"},
		"grafana":    		{Name: "grafana", Repository: "https://charts.bitnami.com/bitnami", Version: "12.1.4"},
		"vault-operator": {Name: "vault-operator", Repository: "oci://ghcr.io/bank-vaults/helm-charts", Version: "1.23.0"},
		"karpenter":    	{Name: "karpenter", Repository: "oci://public.ecr.aws/karpenter", Version: "1.9.0"},
		"cert-manager":   {Name: "cert-manager", Repository: "oci://quay.io/jetstack/charts", Version: "v1.19.4"},
		"redis":      		{Name: "redis", Repository: "https://charts.bitnami.com/bitnami", Version: "21.2.5"},
		"postgresql": 		{Name: "postgresql", Repository: "https://charts.bitnami.com/bitnami", Version: "14.0.5"},
	}

	for _, dep := range chart.Dependencies {
		expectedDep, exists := expectedDeps[dep.Name]
		if !exists {
			t.Errorf("Unexpected dependency %s found in main Chart.yaml", dep.Name)
			continue
		}
		if dep.Repository != expectedDep.Repository || dep.Version != expectedDep.Version {
			t.Errorf("Dependency %s has incorrect details. Expected: %+v, Found: %+v", dep.Name, expectedDep, dep)
		}
	}

	// Assert that the content of all files contains the expected strings
	if !strings.Contains(grafanaChartContent, "grafana") {
		t.Error("charts/grafana/Chart.yaml does not contain the expected string 'grafana'")
	}
	if !strings.Contains(redisChartContent, "redis") {
		t.Error("charts/redis/Chart.yaml does not contain the expected string 'redis'")
	}
	if !strings.Contains(postgresChartContent, "postgres") {
		t.Error("charts/postgresql/Chart.yaml does not contain the expected string 'postgres'")
	}
}
