package ociartifact

import (
	"errors"
	"fmt"
	"os"
	"path"
	"strings"
)

// Repository returns the repository `helm push <chart> <registryURL>` pushes
// to, without the scheme.
func Repository(registryURL, chartName string) (string, error) {
	host, ok := strings.CutPrefix(registryURL, "oci://")
	if !ok {
		return "", fmt.Errorf("registry URL %q must start with oci://", registryURL)
	}
	if strings.Trim(host, "/") == "" {
		return "", fmt.Errorf("registry URL %q has no host", registryURL)
	}
	// Helm joins the two the same way (pkg/pusher/ocipusher.go).
	return path.Join(host, chartName), nil
}

// Tag returns the tag `helm push` uses for a chart version. OCI tags cannot
// contain `+`, so Helm replaces it with `_`.
func Tag(version string) string {
	return strings.ReplaceAll(version, "+", "_")
}

// ReadRegistryURL returns registryURL, or the trimmed contents of
// registryURLFile. Exactly one of the two must be set.
func ReadRegistryURL(registryURL, registryURLFile string) (string, error) {
	if (registryURL == "") == (registryURLFile == "") {
		return "", errors.New("exactly one of -registry_url and -registry_url_file is required")
	}
	if registryURL != "" {
		return registryURL, nil
	}
	contents, err := os.ReadFile(registryURLFile)
	if err != nil {
		return "", fmt.Errorf("reading registry URL file: %w", err)
	}
	url := strings.TrimSpace(string(contents))
	if url == "" {
		return "", fmt.Errorf("registry_url_file %q is empty", registryURLFile)
	}
	return url, nil
}
