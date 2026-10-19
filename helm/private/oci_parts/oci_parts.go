// oci_parts writes the parts of the OCI artifact that `helm push` creates for a
// chart, in the form `rules_img`'s `image_manifest` and `image_push_spec` read.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"path"
	"strings"

	"github.com/periareon/rules_helm/helm/private/oci_digest/ociartifact"
)

// destination returns the repository `helm push <chart> <registryURL>` pushes
// to, without the scheme.
func destination(registryURL, chartName string) (string, error) {
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

// tag returns the tag `helm push` uses for a chart version. OCI tags cannot
// contain `+`, so Helm replaces it with `_`.
func tag(version string) string {
	return strings.ReplaceAll(version, "+", "_")
}

// escapeTemplate makes a value pass through `rules_img`'s Go template expansion
// unchanged.
func escapeTemplate(value string) string {
	return strings.ReplaceAll(value, "{{", `{{"{{"}}`)
}

func readRegistryURL(registryURL, registryURLFile string) (string, error) {
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

func main() {
	chartTgz := flag.String("chart", "", "Path to the Helm chart .tgz file")
	metadataJSON := flag.String("metadata", "", "Path to the chart metadata JSON file")
	registryURL := flag.String("registry_url", "", "Registry URL as given to `helm push`, for example oci://host/path")
	registryURLFile := flag.String("registry_url_file", "", "Path to a file containing the registry URL")
	configOutput := flag.String("config_output", "", "Path to write the config blob")
	annotationsOutput := flag.String("annotations_output", "", "Path to write the manifest annotations as a JSON object")
	tagOutput := flag.String("tag_output", "", "Path to write the tag")
	destinationOutput := flag.String("destination_output", "", "Path to write `<registry>/<repository>`")

	flag.Parse()

	if *chartTgz == "" || *metadataJSON == "" || *configOutput == "" || *annotationsOutput == "" || *tagOutput == "" || *destinationOutput == "" {
		log.Fatal("Required flags: -chart, -metadata, -config_output, -annotations_output, -tag_output, -destination_output")
	}

	url, err := readRegistryURL(*registryURL, *registryURLFile)
	if err != nil {
		log.Fatal(err)
	}

	artifact, err := ociartifact.Load(*chartTgz, *metadataJSON)
	if err != nil {
		log.Fatalf("Error loading chart: %v", err)
	}

	dest, err := destination(url, artifact.Metadata.Name)
	if err != nil {
		log.Fatal(err)
	}

	annotations := make(map[string]string, len(artifact.Annotations))
	for k, v := range artifact.Annotations {
		annotations[k] = escapeTemplate(v)
	}
	annotationsJSON, err := json.Marshal(annotations)
	if err != nil {
		log.Fatalf("Error marshalling annotations: %v", err)
	}

	for path, contents := range map[string][]byte{
		*configOutput:      artifact.ConfigBlob,
		*annotationsOutput: annotationsJSON,
		*tagOutput:         []byte(tag(artifact.Metadata.Version)),
		*destinationOutput: []byte(dest),
	} {
		if err := os.WriteFile(path, contents, 0644); err != nil {
			log.Fatalf("Error writing %s: %v", path, err)
		}
	}
}
