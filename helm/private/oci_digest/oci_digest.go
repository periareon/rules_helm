// oci_digest computes the OCI manifest digest for a Helm chart .tgz.
//
// It constructs the OCI manifest that `helm push` (Helm v4) would create
// and outputs the sha256 digest.
package main

import (
	"flag"
	"log"
	"os"

	"github.com/periareon/rules_helm/helm/private/oci_digest/ociartifact"
)

func main() {
	chartTgz := flag.String("chart", "", "Path to the Helm chart .tgz file")
	metadataJSON := flag.String("metadata", "", "Path to the chart metadata JSON file")
	digestOutput := flag.String("digest_output", "", "Path to write the manifest digest (sha256:...)")
	manifestOutput := flag.String("manifest_output", "", "Optional path to write the OCI manifest bytes")
	configOutput := flag.String("config_output", "", "Optional path to write the OCI config blob bytes")

	flag.Parse()

	if *chartTgz == "" || *metadataJSON == "" || *digestOutput == "" {
		log.Fatal("Required flags: -chart, -metadata, -digest_output")
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
	digest := ociartifact.Digest(manifestBytes)
	if err := os.WriteFile(*digestOutput, []byte(digest.String()), 0644); err != nil {
		log.Fatalf("Error writing digest file: %v", err)
	}

	// The manifest and config blobs are written verbatim, never re-marshalled by
	// a consumer: re-serializing this JSON can reorder keys or change whitespace,
	// which changes the digest above and invalidates every descriptor that
	// references it. A pusher that uploads the blobs itself needs these exact
	// bytes to PUT.
	if *manifestOutput != "" {
		if err := os.WriteFile(*manifestOutput, manifestBytes, 0644); err != nil {
			log.Fatalf("Error writing manifest file: %v", err)
		}
	}

	if *configOutput != "" {
		if err := os.WriteFile(*configOutput, artifact.ConfigBlob, 0644); err != nil {
			log.Fatalf("Error writing config file: %v", err)
		}
	}
}
