// oci_digest computes the OCI manifest digest for a Helm chart .tgz.
//
// It constructs the OCI manifest that `helm push` (Helm v4) would create
// and outputs the sha256 digest. It also outputs the annotations and tag, and,
// given a registry URL, the repository `helm push` would push to.
package main

import (
	"encoding/json"
	"flag"
	"log"
	"os"

	"github.com/periareon/rules_helm/helm/private/oci_digest/ociartifact"
)

func writeFile(path string, contents []byte) {
	if err := os.WriteFile(path, contents, 0644); err != nil {
		log.Fatalf("Error writing %s: %v", path, err)
	}
}

func main() {
	chartTgz := flag.String("chart", "", "Path to the Helm chart .tgz file")
	metadataJSON := flag.String("metadata", "", "Path to the chart metadata JSON file")
	digestOutput := flag.String("digest_output", "", "Path to write the manifest digest (sha256:...)")
	manifestOutput := flag.String("manifest_output", "", "Optional path to write the OCI manifest bytes")
	configOutput := flag.String("config_output", "", "Optional path to write the OCI config blob bytes")
	annotationsOutput := flag.String("annotations_output", "", "Optional path to write the manifest annotations as a JSON object")
	tagOutput := flag.String("tag_output", "", "Optional path to write the tag `helm push` uses")
	registryURL := flag.String("registry_url", "", "Registry URL as given to `helm push`, for example oci://host/path")
	registryURLFile := flag.String("registry_url_file", "", "Path to a file containing the registry URL")
	repositoryOutput := flag.String("repository_output", "", "Optional path to write `<registry>/<repository>`; requires a registry URL")

	flag.Parse()

	if *chartTgz == "" || *metadataJSON == "" || *digestOutput == "" {
		log.Fatal("Required flags: -chart, -metadata, -digest_output")
	}

	if *repositoryOutput == "" && (*registryURL != "" || *registryURLFile != "") {
		log.Fatal("-registry_url and -registry_url_file require -repository_output")
	}

	artifact, err := ociartifact.Load(*chartTgz, *metadataJSON)
	if err != nil {
		log.Fatalf("Error loading chart: %v", err)
	}

	manifestBytes, err := artifact.Manifest()
	if err != nil {
		log.Fatalf("Error marshalling manifest: %v", err)
	}

	// Write digest (no trailing newline)
	writeFile(*digestOutput, []byte(ociartifact.Digest(manifestBytes).String()))

	// The manifest and config blobs are written verbatim, never re-marshalled by
	// a consumer: re-serializing this JSON can reorder keys or change whitespace,
	// which changes the digest above and invalidates every descriptor that
	// references it. A pusher that uploads the blobs itself needs these exact
	// bytes to PUT.
	if *manifestOutput != "" {
		writeFile(*manifestOutput, manifestBytes)
	}

	if *configOutput != "" {
		writeFile(*configOutput, artifact.ConfigBlob)
	}

	if *annotationsOutput != "" {
		annotationsJSON, err := json.Marshal(artifact.Annotations)
		if err != nil {
			log.Fatalf("Error marshalling annotations: %v", err)
		}
		writeFile(*annotationsOutput, annotationsJSON)
	}

	if *tagOutput != "" {
		writeFile(*tagOutput, []byte(ociartifact.Tag(artifact.Metadata.Version)))
	}

	if *repositoryOutput != "" {
		url, err := ociartifact.ReadRegistryURL(*registryURL, *registryURLFile)
		if err != nil {
			log.Fatal(err)
		}
		repository, err := ociartifact.Repository(url, artifact.Metadata.Name)
		if err != nil {
			log.Fatal(err)
		}
		writeFile(*repositoryOutput, []byte(repository))
	}
}
