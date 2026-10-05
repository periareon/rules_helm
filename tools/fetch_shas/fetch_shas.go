// fetch_shas prints the checksums rules_helm pins for a release of helm or kubectl.
//
// Usage:
//
//	bazel run //tools/fetch_shas -- [-tool helm|kubectl] <version>
//
// The output is JSON shaped like the version tables in
// `helm/private/versions.bzl` (SRI integrity strings for helm) and
// `k8s/private/kubectl_versions.bzl` (hex sha256 digests for kubectl).
package main

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

// Format arguments are `{version}`, `{platform}`, `{compression}`.
var HELM_CHECKSUM_URL_TEMPLATE = "https://get.helm.sh/helm-v%s-%s.%s.sha256sum"

// Format arguments are `{version}`, `{os}`, `{arch}`, `{binary}`.
var KUBECTL_CHECKSUM_URL_TEMPLATE = "https://dl.k8s.io/release/v%s/bin/%s/%s/%s.sha256"

var HELM_PLATFORMS = []string{
	"darwin-amd64",
	"darwin-arm64",
	"linux-amd64",
	"linux-arm",
	"linux-arm64",
	"linux-i386",
	"linux-ppc64le",
	"windows-amd64",
}

// Keep in sync with `KUBECTL_PLATFORMS` in `k8s/private/kubectl_versions.bzl`.
var KUBECTL_PLATFORMS = []string{
	"darwin-amd64",
	"darwin-arm64",
	"linux-386",
	"linux-amd64",
	"linux-arm",
	"linux-arm64",
	"linux-ppc64le",
	"linux-s390x",
	"windows-amd64",
	"windows-arm64",
}

// fetchChecksumFile downloads a checksum file and returns its first whitespace
// separated field (the hex digest).
func fetchChecksumFile(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to fetch: %s, status: %d", url, resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	parts := strings.Fields(string(body))
	if len(parts) < 1 {
		return "", fmt.Errorf("unexpected file format: %s", body)
	}

	return parts[0], nil
}

// fetchHelmIntegrity fetches the helm checksum for a platform and returns it
// in Subresource Integrity format.
func fetchHelmIntegrity(version string, platform string) (string, error) {
	compression := "tar.gz"
	if strings.Contains(platform, "windows") {
		compression = "zip"
	}

	// Sanitize platform names.
	if platform == "linux-i386" {
		platform = "linux-386"
	}

	url := fmt.Sprintf(HELM_CHECKSUM_URL_TEMPLATE, version, platform, compression)
	hexChecksum, err := fetchChecksumFile(url)
	if err != nil {
		return "", err
	}

	checksum, err := hex.DecodeString(hexChecksum)
	if err != nil {
		return "", fmt.Errorf("failed to decode hex checksum: %v", err)
	}

	encodedChecksum := base64.StdEncoding.EncodeToString(checksum)
	return fmt.Sprintf("sha256-%s", encodedChecksum), nil
}

// fetchKubectlSha256 fetches the kubectl checksum for a platform and returns
// the hex digest, which is what `repository_ctx.download(sha256 = ...)` expects.
func fetchKubectlSha256(version string, platform string) (string, error) {
	osName, arch, found := strings.Cut(platform, "-")
	if !found {
		return "", fmt.Errorf("invalid platform: %s", platform)
	}

	binary := "kubectl"
	if osName == "windows" {
		binary = "kubectl.exe"
	}

	url := fmt.Sprintf(KUBECTL_CHECKSUM_URL_TEMPLATE, version, osName, arch, binary)
	hexChecksum, err := fetchChecksumFile(url)
	if err != nil {
		return "", err
	}

	if _, err := hex.DecodeString(hexChecksum); err != nil {
		return "", fmt.Errorf("failed to decode hex checksum: %v", err)
	}

	return hexChecksum, nil
}

func main() {
	tool := flag.String("tool", "helm", "The tool to fetch checksums for: `helm` or `kubectl`.")
	flag.Usage = func() {
		fmt.Fprintln(flag.CommandLine.Output(), "Usage: fetch_shas [-tool helm|kubectl] <version>")
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(1)
	}

	version := strings.TrimPrefix(flag.Arg(0), "v")

	var platforms []string
	var fetch func(version string, platform string) (string, error)
	switch *tool {
	case "helm":
		platforms = HELM_PLATFORMS
		fetch = fetchHelmIntegrity
	case "kubectl":
		platforms = KUBECTL_PLATFORMS
		fetch = fetchKubectlSha256
	default:
		log.Fatalf("Unknown tool %q: expected `helm` or `kubectl`", *tool)
	}

	result := make(map[string]map[string]string)
	result[version] = make(map[string]string)

	for _, platform := range platforms {
		checksum, err := fetch(version, platform)
		if err != nil {
			log.Fatalf("Error fetching %s %s-%s: %v\n", *tool, version, platform, err)
		}
		result[version][platform] = checksum
	}

	jsonOutput, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		log.Fatalf("Error generating JSON: %v", err)
	}
	fmt.Println(string(jsonOutput))
}
