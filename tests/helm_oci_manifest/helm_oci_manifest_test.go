package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

const (
	helmConfigMediaType = "application/vnd.cncf.helm.config.v1+json"
	helmChartMediaType  = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
)

// manifestMediaType is the field `rules_img` writes and `helm push` does not.
var manifestMediaType = []byte(`"mediaType":"application/vnd.oci.image.manifest.v1+json",`)

type descriptor struct {
	MediaType   string            `json:"mediaType"`
	Digest      string            `json:"digest"`
	Annotations map[string]string `json:"annotations"`
}

type manifest struct {
	Config      descriptor        `json:"config"`
	Layers      []descriptor      `json:"layers"`
	Annotations map[string]string `json:"annotations"`
}

// pushed is one chart that a `multi_deploy` wrote to the sink.
type pushed struct {
	raw      []byte
	manifest manifest
	layout   string
}

func (p pushed) blob(t *testing.T, digest string) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(p.layout, "blobs", strings.Replace(digest, ":", "/", 1)))
	if err != nil {
		t.Fatalf("Failed to read blob %s: %v", digest, err)
	}
	return data
}

func readRunfile(t *testing.T, envVar string) []byte {
	t.Helper()
	path, err := runfiles.Rlocation(os.Getenv(envVar))
	if err != nil {
		t.Fatalf("Failed to locate %s: %v", envVar, err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("Failed to read %s: %v", envVar, err)
	}
	return data
}

func sha256Digest(data []byte) string {
	h := sha256.Sum256(data)
	return "sha256:" + hex.EncodeToString(h[:])
}

// deploy runs a `multi_deploy` with an OCI layout sink, which needs no
// registry, and returns what it wrote keyed by image reference.
func deploy(t *testing.T, envVar string) map[string]pushed {
	t.Helper()

	launcher, err := runfiles.Rlocation(os.Getenv(envVar))
	if err != nil {
		t.Fatalf("Failed to locate %s: %v", envVar, err)
	}
	runfilesEnv, err := runfiles.Env()
	if err != nil {
		t.Fatal(err)
	}
	layout := filepath.Join(t.TempDir(), "layout")

	cmd := exec.Command(launcher, "--sink", "oci:"+layout)
	cmd.Env = append(os.Environ(), runfilesEnv...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%s failed: %v\n%s", envVar, err, out)
	}

	var index struct {
		Manifests []descriptor `json:"manifests"`
	}
	indexJSON, err := os.ReadFile(filepath.Join(layout, "index.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(indexJSON, &index); err != nil {
		t.Fatal(err)
	}

	result := map[string]pushed{}
	for _, d := range index.Manifests {
		p := pushed{layout: layout}
		p.raw = p.blob(t, d.Digest)
		if err := json.Unmarshal(p.raw, &p.manifest); err != nil {
			t.Fatal(err)
		}
		result[d.Annotations["io.containerd.image.name"]] = p
	}
	return result
}

// checkChart compares a pushed chart with the chart .tgz and the digest
// helm_oci_digest predicts for `helm push`.
func checkChart(t *testing.T, p pushed, chartEnv, digestEnv string) {
	t.Helper()

	if got := p.manifest.Config.MediaType; got != helmConfigMediaType {
		t.Errorf("config mediaType = %q, want %q", got, helmConfigMediaType)
	}
	if len(p.manifest.Layers) != 1 {
		t.Fatalf("got %d layers, want 1", len(p.manifest.Layers))
	}
	if got := p.manifest.Layers[0].MediaType; got != helmChartMediaType {
		t.Errorf("layer mediaType = %q, want %q", got, helmChartMediaType)
	}
	if !bytes.Equal(p.blob(t, p.manifest.Layers[0].Digest), readRunfile(t, chartEnv)) {
		t.Errorf("layer is not the chart .tgz")
	}

	if bytes.Count(p.raw, manifestMediaType) != 1 {
		t.Fatalf("manifest does not have the top-level mediaType field once: %s", p.raw)
	}
	helmManifest := bytes.Replace(p.raw, manifestMediaType, nil, 1)
	if got, want := sha256Digest(helmManifest), string(readRunfile(t, digestEnv)); got != want {
		t.Errorf("manifest without mediaType has digest %s, helm_oci_digest predicts %s", got, want)
	}
}

func TestDeploy(t *testing.T) {
	charts := deploy(t, "DEPLOY")
	if len(charts) != 3 {
		t.Fatalf("got references %v, want 3", charts)
	}

	simple, ok := charts["localhost:5051/charts/simple:0.1.0"]
	if !ok {
		t.Fatalf("simple is missing from %v", charts)
	}
	checkChart(t, simple, "SIMPLE_CHART", "SIMPLE_DIGEST")
	if !bytes.Equal(simple.blob(t, simple.manifest.Config.Digest), readRunfile(t, "HELM_PUSH_CONFIG")) {
		t.Errorf("config blob differs from the one `helm push` sent")
	}

	// The pushed manifest is the `helm push` manifest plus a top-level
	// mediaType. Once `helm_oci_manifest` has `rules_img` leave the field out,
	// this fails and the two manifests are equal.
	want := bytes.Replace(readRunfile(t, "HELM_PUSH_MANIFEST"), []byte(`{"schemaVersion":2,`), append([]byte(`{"schemaVersion":2,`), manifestMediaType...), 1)
	if !bytes.Equal(simple.raw, want) {
		t.Errorf("manifest = %s\nwant %s", simple.raw, want)
	}

	template, ok := charts["localhost:5051/charts/template:0.1.0"]
	if !ok {
		t.Fatalf("template is missing from %v", charts)
	}
	checkChart(t, template, "TEMPLATE_CHART", "TEMPLATE_DIGEST")
	if got, want := template.manifest.Annotations["org.opencontainers.image.description"], "Renders {{ .Values.name }} and a lone {{"; got != want {
		t.Errorf("description annotation = %q, want %q", got, want)
	}

	plus, ok := charts["localhost:5051/charts/plus:0.1.0_build.1"]
	if !ok {
		t.Fatalf("plus is missing from %v", charts)
	}
	checkChart(t, plus, "PLUS_CHART", "PLUS_DIGEST")
}

// TestRegistryURLForms expects a trailing slash and `registry_url_file` to
// push the same manifest to the same reference as a plain `registry_url`.
func TestRegistryURLForms(t *testing.T) {
	const ref = "localhost:5051/charts/simple:0.1.0"
	want := deploy(t, "DEPLOY")[ref].raw

	for _, envVar := range []string{"DEPLOY_TRAILING_SLASH", "DEPLOY_URL_FILE"} {
		charts := deploy(t, envVar)
		p, ok := charts[ref]
		if !ok || len(charts) != 1 {
			t.Errorf("%s pushed %v, want only %s", envVar, charts, ref)
			continue
		}
		if !bytes.Equal(p.raw, want) {
			t.Errorf("%s manifest = %s\nwant %s", envVar, p.raw, want)
		}
	}
}
