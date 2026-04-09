// oci_digest computes the OCI manifest digest for a Helm chart .tgz.
//
// It constructs the OCI manifest that `helm push` (Helm v4) would create
// and outputs the sha256 digest. In reproducible mode, a fixed epoch
// timestamp is used; otherwise the .tgz file's mtime is used, matching
// what `helm push` produces.
package main

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"time"

	godigest "github.com/opencontainers/go-digest"
	specs "github.com/opencontainers/image-spec/specs-go"
	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
	"sigs.k8s.io/yaml"

	"github.com/periareon/rules_helm/helm/private/oci_digest/chartmeta"
)

// Helm-specific OCI media types.
const (
	HelmConfigMediaType = "application/vnd.cncf.helm.config.v1+json"
	HelmChartMediaType  = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
)


func sha256Digest(data []byte) godigest.Digest {
	h := sha256.Sum256(data)
	return godigest.NewDigestFromEncoded(godigest.SHA256, hex.EncodeToString(h[:]))
}

func readChartYAMLFromTgz(tgzPath string) ([]byte, error) {
	file, err := os.Open(tgzPath)
	if err != nil {
		return nil, fmt.Errorf("opening tarball %s: %w", tgzPath, err)
	}
	defer file.Close()

	gz, err := gzip.NewReader(file)
	if err != nil {
		return nil, fmt.Errorf("creating gzip reader: %w", err)
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("reading tar: %w", err)
		}

		// Chart.yaml is at <chart-name>/Chart.yaml
		parts := strings.Split(header.Name, "/")
		if len(parts) == 2 && parts[1] == "Chart.yaml" {
			return io.ReadAll(tr)
		}
	}

	return nil, errors.New("Chart.yaml not found in tarball")
}

// generateAnnotations replicates Helm v4's unexported generateOCIAnnotations
// (pkg/registry/chart.go). When reproducible, uses a fixed creation timestamp;
// otherwise uses the provided creation time from the chart .tgz mtime.
func generateAnnotations(meta *chartmeta.Metadata, creationTime string) map[string]string {
	annotations := make(map[string]string)

	// Helm's addToMap pattern: only set if non-empty after trim
	addToMap := func(key, value string) {
		if len(strings.TrimSpace(value)) > 0 {
			annotations[key] = value
		}
	}

	addToMap(ocispec.AnnotationDescription, meta.Description)
	addToMap(ocispec.AnnotationTitle, meta.Name)
	addToMap(ocispec.AnnotationVersion, meta.Version)
	addToMap(ocispec.AnnotationURL, meta.Home)

	annotations[ocispec.AnnotationCreated] = creationTime

	if len(meta.Sources) > 0 {
		addToMap(ocispec.AnnotationSource, meta.Sources[0])
	}

	if len(meta.Maintainers) > 0 {
		var sb strings.Builder
		for i, m := range meta.Maintainers {
			if len(m.Name) > 0 {
				sb.WriteString(m.Name)
			}
			if len(m.Email) > 0 {
				sb.WriteString(" (")
				sb.WriteString(m.Email)
				sb.WriteString(")")
			}
			if i < len(meta.Maintainers)-1 {
				sb.WriteString(", ")
			}
		}
		addToMap(ocispec.AnnotationAuthors, sb.String())
	}

	// Merge custom annotations from Chart.yaml, but never override title/version
	for k, v := range meta.Annotations {
		if k == ocispec.AnnotationTitle || k == ocispec.AnnotationVersion {
			continue
		}
		annotations[k] = v
	}

	return annotations
}

func main() {
	chartTgz := flag.String("chart", "", "Path to the Helm chart .tgz file")
	metadataJSON := flag.String("metadata", "", "Path to the chart metadata JSON file (name + version)")
	digestOutput := flag.String("digest_output", "", "Path to write the manifest digest (sha256:...)")

	flag.Parse()

	if *chartTgz == "" || *metadataJSON == "" || *digestOutput == "" {
		log.Fatal("Required flags: -chart, -metadata, -digest_output")
	}

	// Determine the creation timestamp.
	// Helm v4 uses stat.ModTime().Format(time.RFC3339) on the .tgz file
	// (see pkg/pusher/ocipusher.go). We format in UTC so the digest is
	// timezone-independent (the push side sets TZ=UTC too).
	info, err := os.Stat(*chartTgz)
	if err != nil {
		log.Fatalf("Error stat'ing chart .tgz: %v", err)
	}
	creationTime := info.ModTime().UTC().Format(time.RFC3339)

	// Read Chart.yaml from the .tgz
	chartYAML, err := readChartYAMLFromTgz(*chartTgz)
	if err != nil {
		log.Fatalf("Error reading Chart.yaml from .tgz: %v", err)
	}

	// Parse into chartmeta.Metadata (vendored from Helm — guarantees identical JSON tags)
	var chartMeta chartmeta.Metadata
	if err := yaml.Unmarshal(chartYAML, &chartMeta); err != nil {
		log.Fatalf("Error parsing Chart.yaml: %v", err)
	}

	// Apply the same field mutations Helm's loader performs before serialization:
	// sanitizeString on all text fields, APIVersion defaulting to "v1".
	chartmeta.PrepareForSerialization(&chartMeta)

	// Serialize config blob as JSON — byte-identical to helm push
	configBlob, err := json.Marshal(&chartMeta)
	if err != nil {
		log.Fatalf("Error marshalling config blob: %v", err)
	}

	// Read chart .tgz for layer digest
	tgzBytes, err := os.ReadFile(*chartTgz)
	if err != nil {
		log.Fatalf("Error reading chart .tgz: %v", err)
	}

	// Compute content digests
	configDigest := sha256Digest(configBlob)
	tgzDigest := sha256Digest(tgzBytes)

	// Build OCI annotations
	annotations := generateAnnotations(&chartMeta, creationTime)

	// Build OCI manifest using the same types as Helm v4
	manifest := ocispec.Manifest{
		Versioned: specs.Versioned{SchemaVersion: 2},
		Config: ocispec.Descriptor{
			MediaType: HelmConfigMediaType,
			Digest:    configDigest,
			Size:      int64(len(configBlob)),
		},
		Layers: []ocispec.Descriptor{
			{
				MediaType: HelmChartMediaType,
				Digest:    tgzDigest,
				Size:      int64(len(tgzBytes)),
			},
		},
		Annotations: annotations,
	}

	manifestBytes, err := json.Marshal(manifest)
	if err != nil {
		log.Fatalf("Error marshalling manifest: %v", err)
	}

	// Compute manifest digest
	digest := sha256Digest(manifestBytes)

	// Write digest (no trailing newline)
	if err := os.WriteFile(*digestOutput, []byte(digest.String()), 0644); err != nil {
		log.Fatalf("Error writing digest file: %v", err)
	}
}
