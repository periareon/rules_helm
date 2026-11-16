// layout_manifest copies the root manifest (or index) out of an OCI image
// layout so it can be hashed and shipped like any other file.
//
// The layout's `index.json` names the manifest by digest and the bytes live
// under `blobs/<algorithm>/<encoded>`. Only the first entry is used, matching
// what a registry would be told to tag.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
)

type descriptor struct {
	Digest string `json:"digest"`
}

type index struct {
	Manifests []descriptor `json:"manifests"`
}

func run(layout string, output string) error {
	indexPath := filepath.Join(layout, "index.json")
	content, err := os.ReadFile(indexPath)
	if err != nil {
		return err
	}

	var parsed index
	if err := json.Unmarshal(content, &parsed); err != nil {
		return fmt.Errorf("parse %s: %w", indexPath, err)
	}
	if len(parsed.Manifests) == 0 {
		return fmt.Errorf("%s lists no manifests", indexPath)
	}

	digest := parsed.Manifests[0].Digest
	algorithm, encoded, ok := strings.Cut(digest, ":")
	if !ok || algorithm == "" || encoded == "" {
		return fmt.Errorf("%s: malformed digest %q", indexPath, digest)
	}

	manifest, err := os.ReadFile(filepath.Join(layout, "blobs", algorithm, encoded))
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(output), 0755); err != nil {
		return err
	}
	return os.WriteFile(output, manifest, 0644)
}

func main() {
	layout := flag.String("layout", "", "The path to an OCI image layout directory")
	output := flag.String("output", "", "The path to write the root manifest to")
	flag.Parse()

	if *layout == "" || *output == "" {
		log.Fatal("-layout and -output are required")
	}

	if err := run(*layout, *output); err != nil {
		log.Fatal(err)
	}
}
