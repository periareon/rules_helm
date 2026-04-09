// oci_digest computes the OCI manifest digest for a Helm chart .tgz.
//
// It constructs the OCI manifest that would be created by `helm push`,
// minus the non-deterministic timestamp annotation, and outputs the
// sha256 digest. This allows the digest to be known at build time,
// before any push to a registry.
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

	"path/filepath"

	"gopkg.in/yaml.v3"
)

// OCIIndex is the OCI image index (index.json) per the OCI Image Layout spec.
type OCIIndex struct {
	SchemaVersion int             `json:"schemaVersion"`
	MediaType     string          `json:"mediaType"`
	Manifests     []OCIDescriptor `json:"manifests"`
}

// HelmChartMetadata mirrors helm.sh/helm/v3/pkg/chart.Metadata field ordering.
// The JSON field order must match Helm's Go struct serialization to produce
// identical config blob bytes as `helm push`.
//
// Both yaml and json tags are needed: yaml for unmarshalling from Chart.yaml,
// json for marshalling the config blob with the correct field order.
// Fields use omitempty on json only where Helm does.
type HelmChartMetadata struct {
	Name         string            `yaml:"name" json:"name"`
	Home         string            `yaml:"home,omitempty" json:"home,omitempty"`
	Sources      []string          `yaml:"sources,omitempty" json:"sources,omitempty"`
	Version      string            `yaml:"version" json:"version"`
	Description  string            `yaml:"description,omitempty" json:"description,omitempty"`
	Keywords     []string          `yaml:"keywords,omitempty" json:"keywords,omitempty"`
	Maintainers  []HelmMaintainer  `yaml:"maintainers,omitempty" json:"maintainers,omitempty"`
	Icon         string            `yaml:"icon,omitempty" json:"icon,omitempty"`
	APIVersion   string            `yaml:"apiVersion" json:"apiVersion"`
	Condition    string            `yaml:"condition,omitempty" json:"condition,omitempty"`
	Tags         string            `yaml:"tags,omitempty" json:"tags,omitempty"`
	AppVersion   string            `yaml:"appVersion,omitempty" json:"appVersion,omitempty"`
	Deprecated   bool              `yaml:"deprecated,omitempty" json:"deprecated,omitempty"`
	Annotations  map[string]string `yaml:"annotations,omitempty" json:"annotations,omitempty"`
	KubeVersion  string            `yaml:"kubeVersion,omitempty" json:"kubeVersion,omitempty"`
	Dependencies []HelmDependency  `yaml:"dependencies,omitempty" json:"dependencies,omitempty"`
	Type         string            `yaml:"type,omitempty" json:"type,omitempty"`
}

type HelmMaintainer struct {
	Name  string `yaml:"name" json:"name"`
	Email string `yaml:"email,omitempty" json:"email,omitempty"`
	URL   string `yaml:"url,omitempty" json:"url,omitempty"`
}

// HelmDependency uses `json:"repository"` without omitempty because Helm
// serializes the empty string for repository (not omitting it).
type HelmDependency struct {
	Name         string   `yaml:"name" json:"name"`
	Version      string   `yaml:"version,omitempty" json:"version,omitempty"`
	Repository   string   `yaml:"repository" json:"repository"`
	Condition    string   `yaml:"condition,omitempty" json:"condition,omitempty"`
	Tags         []string `yaml:"tags,omitempty" json:"tags,omitempty"`
	Enabled      *bool    `yaml:"enabled,omitempty" json:"enabled,omitempty"`
	ImportValues []any    `yaml:"import-values,omitempty" json:"import-values,omitempty"`
	Alias        string   `yaml:"alias,omitempty" json:"alias,omitempty"`
}

// OCIDescriptor is a content descriptor per OCI spec.
type OCIDescriptor struct {
	MediaType string `json:"mediaType"`
	Digest    string `json:"digest"`
	Size      int64  `json:"size"`
}

// OCIManifest is an OCI image manifest for a Helm chart.
type OCIManifest struct {
	SchemaVersion int               `json:"schemaVersion"`
	Config        OCIDescriptor     `json:"config"`
	Layers        []OCIDescriptor   `json:"layers"`
	Annotations   map[string]string `json:"annotations,omitempty"`
}

func sha256Bytes(data []byte) string {
	h := sha256.Sum256(data)
	return "sha256:" + hex.EncodeToString(h[:])
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

// generateAnnotations produces deterministic OCI annotations from Chart.yaml
// metadata, matching the fields that `helm push` sets via
// generateChartOCIAnnotations (helm.sh/helm/v3/pkg/registry/chart.go).
//
// Deliberately omits org.opencontainers.image.created — that's a push-time
// timestamp and would make the manifest non-deterministic.
func generateAnnotations(meta HelmChartMetadata) map[string]string {
	annotations := make(map[string]string)

	// Always set title and version (Helm treats these as immutable)
	annotations["org.opencontainers.image.title"] = meta.Name
	annotations["org.opencontainers.image.version"] = meta.Version

	if meta.Description != "" {
		annotations["org.opencontainers.image.description"] = meta.Description
	}
	if meta.Home != "" {
		annotations["org.opencontainers.image.url"] = meta.Home
	}
	if len(meta.Sources) > 0 {
		annotations["org.opencontainers.image.source"] = meta.Sources[0]
	}
	if len(meta.Maintainers) > 0 {
		var authors []string
		for _, m := range meta.Maintainers {
			author := m.Name
			if m.Email != "" {
				author += " (" + m.Email + ")"
			}
			authors = append(authors, author)
		}
		annotations["org.opencontainers.image.authors"] = strings.Join(authors, ", ")
	}

	// Copy custom annotations from Chart.yaml, but never override title/version
	for k, v := range meta.Annotations {
		if k == "org.opencontainers.image.title" || k == "org.opencontainers.image.version" {
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
	manifestOutput := flag.String("manifest_output", "", "Path to write the OCI manifest JSON")
	configOutput := flag.String("config_output", "", "Path to write the config blob JSON")
	layoutOutput := flag.String("layout_output", "", "Path to write the OCI layout directory (for crane push)")

	flag.Parse()

	if *chartTgz == "" || *metadataJSON == "" || *digestOutput == "" {
		log.Fatal("Required flags: -chart, -metadata, -digest_output")
	}

	// Read Chart.yaml from the .tgz
	chartYAML, err := readChartYAMLFromTgz(*chartTgz)
	if err != nil {
		log.Fatalf("Error reading Chart.yaml from .tgz: %v", err)
	}

	// Parse into HelmChartMetadata to get Helm's Go struct field ordering
	var chartMeta HelmChartMetadata
	if err := yaml.Unmarshal(chartYAML, &chartMeta); err != nil {
		log.Fatalf("Error parsing Chart.yaml: %v", err)
	}

	// Serialize config blob as JSON with Helm's field ordering
	configBlob, err := json.Marshal(chartMeta)
	if err != nil {
		log.Fatalf("Error marshalling config blob: %v", err)
	}

	// Read chart .tgz for layer digest
	tgzBytes, err := os.ReadFile(*chartTgz)
	if err != nil {
		log.Fatalf("Error reading chart .tgz: %v", err)
	}

	// Build deterministic OCI annotations from Chart.yaml metadata.
	// Matches helm.sh/helm/v3/pkg/registry.generateChartOCIAnnotations,
	// except org.opencontainers.image.created (non-deterministic timestamp).
	annotations := generateAnnotations(chartMeta)

	// Build OCI manifest
	manifest := OCIManifest{
		SchemaVersion: 2,
		Config: OCIDescriptor{
			MediaType: "application/vnd.cncf.helm.config.v1+json",
			Digest:    sha256Bytes(configBlob),
			Size:      int64(len(configBlob)),
		},
		Layers: []OCIDescriptor{
			{
				MediaType: "application/vnd.cncf.helm.chart.content.v1.tar+gzip",
				Digest:    sha256Bytes(tgzBytes),
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
	digest := sha256Bytes(manifestBytes)

	// Write outputs
	if err := os.WriteFile(*digestOutput, []byte(digest), 0644); err != nil {
		log.Fatalf("Error writing digest file: %v", err)
	}

	if *manifestOutput != "" {
		if err := os.WriteFile(*manifestOutput, manifestBytes, 0644); err != nil {
			log.Fatalf("Error writing manifest file: %v", err)
		}
	}

	if *configOutput != "" {
		if err := os.WriteFile(*configOutput, configBlob, 0644); err != nil {
			log.Fatalf("Error writing config file: %v", err)
		}
	}

	if *layoutOutput != "" {
		if err := writeOCILayout(*layoutOutput, digest, manifestBytes, configBlob, tgzBytes); err != nil {
			log.Fatalf("Error writing OCI layout: %v", err)
		}
	}
}

// writeOCILayout creates a directory in OCI image layout format that
// crane push can consume directly.
func writeOCILayout(dir string, digest string, manifestBytes, configBlob, tgzBytes []byte) error {
	blobDir := filepath.Join(dir, "blobs", "sha256")
	if err := os.MkdirAll(blobDir, 0755); err != nil {
		return fmt.Errorf("creating blobs dir: %w", err)
	}

	// Write oci-layout per OCI Image Layout spec
	ociLayout := []byte("{\n    \"imageLayoutVersion\": \"1.0.0\"\n}")
	if err := os.WriteFile(filepath.Join(dir, "oci-layout"), ociLayout, 0644); err != nil {
		return fmt.Errorf("writing oci-layout: %w", err)
	}

	// Write blobs: config, chart .tgz, manifest
	configDigest := sha256Bytes(configBlob)
	tgzDigest := sha256Bytes(tgzBytes)
	manifestDigest := digest

	if err := os.WriteFile(filepath.Join(blobDir, trimSHA(configDigest)), configBlob, 0644); err != nil {
		return fmt.Errorf("writing config blob: %w", err)
	}
	if err := os.WriteFile(filepath.Join(blobDir, trimSHA(tgzDigest)), tgzBytes, 0644); err != nil {
		return fmt.Errorf("writing chart blob: %w", err)
	}
	if err := os.WriteFile(filepath.Join(blobDir, trimSHA(manifestDigest)), manifestBytes, 0644); err != nil {
		return fmt.Errorf("writing manifest blob: %w", err)
	}

	// Write index.json per OCI Image Index spec
	index := OCIIndex{
		SchemaVersion: 2,
		MediaType:     "application/vnd.oci.image.index.v1+json",
		Manifests: []OCIDescriptor{
			{
				MediaType: "application/vnd.oci.image.manifest.v1+json",
				Digest:    manifestDigest,
				Size:      int64(len(manifestBytes)),
			},
		},
	}
	indexBytes, err := json.Marshal(index)
	if err != nil {
		return fmt.Errorf("marshalling index.json: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "index.json"), indexBytes, 0644); err != nil {
		return fmt.Errorf("writing index.json: %w", err)
	}

	return nil
}

// trimSHA removes the "sha256:" prefix from a digest string.
func trimSHA(digest string) string {
	return strings.TrimPrefix(digest, "sha256:")
}
