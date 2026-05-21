package main

import (
	"log"
	"os"
	"regexp"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

func main() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)

	outputRloc := os.Getenv("HELM_COMMAND_OUTPUT")
	if outputRloc == "" {
		log.Fatal("HELM_COMMAND_OUTPUT is not set")
	}

	pattern := os.Getenv("EXPECTED_PATTERN")
	if pattern == "" {
		log.Fatal("EXPECTED_PATTERN is not set")
	}

	r, err := runfiles.New()
	if err != nil {
		log.Fatalf("Failed to init runfiles: %v", err)
	}

	outputPath, err := r.Rlocation(outputRloc)
	if err != nil {
		log.Fatalf("Failed to locate %s: %v", outputRloc, err)
	}

	content, err := os.ReadFile(outputPath)
	if err != nil {
		log.Fatalf("Failed to read %s: %v", outputPath, err)
	}

	re, err := regexp.Compile(pattern)
	if err != nil {
		log.Fatalf("Invalid regex %q: %v", pattern, err)
	}

	if !re.Match(content) {
		log.Fatalf("Pattern %q not found in output:\n%s", pattern, content)
	}
}
