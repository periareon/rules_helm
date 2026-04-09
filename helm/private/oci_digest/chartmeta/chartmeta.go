// Package chartmeta contains vendored type definitions from helm.sh/helm/v4/pkg/chart/v2.
//
// Why vendor instead of importing helm.sh/helm/v4 directly?
//
// The Helm v4 SDK pulls in a massive transitive dependency tree (k8s client-go,
// API machinery, etc.) and triggers a panic in pkg/chart/common/capabilities.go
// when debug.ReadBuildInfo() is unavailable — which is the case under Bazel's Go
// toolchain. Working around the panic requires a go_deps.module_override patch,
// but module_override only works in the root Bazel module, forcing every consumer
// of rules_helm to replicate it.
//
// The only thing the oci_digest tool needs from Helm is the Metadata struct (and
// its field types) so that json.Marshal produces byte-identical output to what
// helm push creates. Vendoring these three structs plus the sanitization function
// eliminates the Helm dependency entirely.
//
// Source: helm.sh/helm/v4 v4.1.4
//   - pkg/chart/v2/metadata.go
//   - pkg/chart/v2/dependency.go
//   - pkg/chart/v2/chart.go (constant only)
package chartmeta

import (
	"strings"
	"unicode"
)

// ---------- Copied from helm.sh/helm/v4@v4.1.4/pkg/chart/v2/chart.go ----------

const APIVersionV1 = "v1"

// ---------- Copied from helm.sh/helm/v4@v4.1.4/pkg/chart/v2/metadata.go ----------

// Metadata for a Chart file. This models the structure of a Chart.yaml file.
type Metadata struct {
	// The name of the chart. Required.
	Name string `json:"name,omitempty"`
	// The URL to a relevant project page, git repo, or contact person
	Home string `json:"home,omitempty"`
	// Source is the URL to the source code of this chart
	Sources []string `json:"sources,omitempty"`
	// A version string of the chart. Required.
	Version string `json:"version,omitempty"`
	// A one-sentence description of the chart
	Description string `json:"description,omitempty"`
	// A list of string keywords
	Keywords []string `json:"keywords,omitempty"`
	// A list of name and URL/email address combinations for the maintainer(s)
	Maintainers []*Maintainer `json:"maintainers,omitempty"`
	// The URL to an icon file.
	Icon string `json:"icon,omitempty"`
	// The API Version of this chart. Required.
	APIVersion string `json:"apiVersion,omitempty"`
	// The condition to check to enable chart
	Condition string `json:"condition,omitempty"`
	// The tags to check to enable chart
	Tags string `json:"tags,omitempty"`
	// The version of the application enclosed inside of this chart.
	AppVersion string `json:"appVersion,omitempty"`
	// Whether or not this chart is deprecated
	Deprecated bool `json:"deprecated,omitempty"`
	// Annotations are additional mappings uninterpreted by Helm,
	// made available for inspection by other applications.
	Annotations map[string]string `json:"annotations,omitempty"`
	// KubeVersion is a SemVer constraint specifying the version of Kubernetes required.
	KubeVersion string `json:"kubeVersion,omitempty"`
	// Dependencies are a list of dependencies for a chart.
	Dependencies []*Dependency `json:"dependencies,omitempty"`
	// Specifies the chart type: application or library
	Type string `json:"type,omitempty"`
}

// Maintainer describes a Chart maintainer.
type Maintainer struct {
	// Name is a user name or organization name
	Name string `json:"name,omitempty"`
	// Email is an optional email address to contact the named maintainer
	Email string `json:"email,omitempty"`
	// URL is an optional URL to an address for the named maintainer
	URL string `json:"url,omitempty"`
}

// ---------- Copied from helm.sh/helm/v4@v4.1.4/pkg/chart/v2/dependency.go ----------

// Dependency describes a chart upon which another chart depends.
type Dependency struct {
	Name        string        `json:"name" yaml:"name"`
	Version     string        `json:"version,omitempty" yaml:"version,omitempty"`
	Repository  string        `json:"repository" yaml:"repository"`
	Condition   string        `json:"condition,omitempty" yaml:"condition,omitempty"`
	Tags        []string      `json:"tags,omitempty" yaml:"tags,omitempty"`
	Enabled     bool          `json:"enabled,omitempty" yaml:"enabled,omitempty"`
	ImportValues []interface{} `json:"import-values,omitempty" yaml:"import-values,omitempty"`
	Alias       string        `json:"alias,omitempty" yaml:"alias,omitempty"`
}

// ---------- Copied from helm.sh/helm/v4@v4.1.4/pkg/chart/v2/metadata.go ----------

// sanitizeString normalizes spaces and removes non-printable characters.
func sanitizeString(str string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) {
			return ' '
		}
		if unicode.IsPrint(r) {
			return r
		}
		return -1
	}, str)
}

// ---------- New: extracts the mutation side-effects of Helm's Validate() ----------

// PrepareForSerialization applies the same field mutations that Helm's
// loader.LoadFiles -> Chart.Validate -> Metadata.Validate chain performs
// before json.Marshal. This ensures byte-identical config blobs.
//
// It intentionally skips all validation checks (semver, name, type) —
// the tool's job is to predict the digest, not reject bad charts.
func PrepareForSerialization(md *Metadata) {
	// Matches Metadata.Validate() in metadata.go
	md.Name = sanitizeString(md.Name)
	md.Description = sanitizeString(md.Description)
	md.Home = sanitizeString(md.Home)
	md.Icon = sanitizeString(md.Icon)
	md.Condition = sanitizeString(md.Condition)
	md.Tags = sanitizeString(md.Tags)
	md.AppVersion = sanitizeString(md.AppVersion)
	md.KubeVersion = sanitizeString(md.KubeVersion)
	for i := range md.Sources {
		md.Sources[i] = sanitizeString(md.Sources[i])
	}
	for i := range md.Keywords {
		md.Keywords[i] = sanitizeString(md.Keywords[i])
	}

	// Matches loader.LoadFiles() in load.go: default to v1 if unset.
	if md.APIVersion == "" {
		md.APIVersion = APIVersionV1
	}

	// Matches Maintainer.Validate() in metadata.go
	for _, m := range md.Maintainers {
		if m != nil {
			m.Name = sanitizeString(m.Name)
			m.Email = sanitizeString(m.Email)
			m.URL = sanitizeString(m.URL)
		}
	}

	// Matches Dependency.Validate() in dependency.go
	for _, d := range md.Dependencies {
		if d != nil {
			d.Name = sanitizeString(d.Name)
			d.Version = sanitizeString(d.Version)
			d.Repository = sanitizeString(d.Repository)
			d.Condition = sanitizeString(d.Condition)
			for i := range d.Tags {
				d.Tags[i] = sanitizeString(d.Tags[i])
			}
		}
	}
}
