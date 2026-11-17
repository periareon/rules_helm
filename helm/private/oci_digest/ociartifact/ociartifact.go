// Package ociartifact builds the parts of the OCI artifact that `helm push`
// (Helm v4) creates for a chart .tgz.
package ociartifact

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

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

// Digest returns the sha256 digest of data.
func Digest(data []byte) godigest.Digest {
	h := sha256.Sum256(data)
	return godigest.NewDigestFromEncoded(godigest.SHA256, hex.EncodeToString(h[:]))
}

// Artifact holds the config blob, layer and annotations of a chart's OCI artifact.
type Artifact struct {
	// Metadata is the chart's Chart.yaml after Helm's serialization mutations.
	Metadata chartmeta.Metadata
	// ConfigBlob is the config blob, byte-identical to the one `helm push` sends.
	ConfigBlob []byte
	// Chart is the chart .tgz, which is the only layer.
	Chart       []byte
	Annotations map[string]string
}

// Load reads a chart .tgz and the metadata.json written alongside it by
// helm_package.
func Load(chartPath, metadataPath string) (*Artifact, error) {
	metadataBytes, err := os.ReadFile(metadataPath)
	if err != nil {
		return nil, fmt.Errorf("reading metadata file: %w", err)
	}
	var metadata struct {
		Created string `json:"created"`
	}
	if err := json.Unmarshal(metadataBytes, &metadata); err != nil {
		return nil, fmt.Errorf("parsing metadata JSON: %w", err)
	}
	if metadata.Created == "" {
		return nil, errors.New("metadata.json missing required `created` field; charts from helm_import are not supported")
	}

	chartYAML, err := readChartYAMLFromTgz(chartPath)
	if err != nil {
		return nil, fmt.Errorf("reading Chart.yaml from .tgz: %w", err)
	}

	// Parse into chartmeta.Metadata (vendored from Helm — guarantees identical JSON tags)
	var chartMeta chartmeta.Metadata
	if err := yaml.Unmarshal(chartYAML, &chartMeta); err != nil {
		return nil, fmt.Errorf("parsing Chart.yaml: %w", err)
	}

	// Apply the same field mutations Helm's loader performs before serialization:
	// sanitizeString on all text fields, APIVersion defaulting to "v1".
	chartmeta.PrepareForSerialization(&chartMeta)

	// Serialize config blob as JSON — byte-identical to helm push
	configBlob, err := json.Marshal(&chartMeta)
	if err != nil {
		return nil, fmt.Errorf("marshalling config blob: %w", err)
	}

	chart, err := os.ReadFile(chartPath)
	if err != nil {
		return nil, fmt.Errorf("reading chart .tgz: %w", err)
	}

	return &Artifact{
		Metadata:    chartMeta,
		ConfigBlob:  configBlob,
		Chart:       chart,
		Annotations: generateAnnotations(&chartMeta, metadata.Created),
	}, nil
}

// Manifest returns the manifest `helm push` creates, using the same types as Helm v4.
func (a *Artifact) Manifest() ([]byte, error) {
	manifest := ocispec.Manifest{
		Versioned: specs.Versioned{SchemaVersion: 2},
		Config: ocispec.Descriptor{
			MediaType: HelmConfigMediaType,
			Digest:    Digest(a.ConfigBlob),
			Size:      int64(len(a.ConfigBlob)),
		},
		Layers: []ocispec.Descriptor{
			{
				MediaType: HelmChartMediaType,
				Digest:    Digest(a.Chart),
				Size:      int64(len(a.Chart)),
			},
		},
		Annotations: a.Annotations,
	}
	return json.Marshal(manifest)
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
// (pkg/registry/chart.go). creationTime is the `created` value helm_package
// records. Annotations from Chart.yaml override every key except title and
// version.
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

	for k, v := range meta.Annotations {
		if k == ocispec.AnnotationTitle || k == ocispec.AnnotationVersion {
			continue
		}
		annotations[k] = v
	}

	return annotations
}
