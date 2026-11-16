package main

import (
	"errors"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

// The modules released from this repository. Each has a `MODULE.bazel` whose
// version must match `version.bzl`, and the extension modules must depend on
// the `rules_helm` released alongside them.
var modules = []string{
	"rules_helm",
	"rules_helm_img",
	"rules_helm_oci",
}

var rulesHelmDep = regexp.MustCompile(`(?m)^bazel_dep\(name = "rules_helm", version = "([^"]*)"`)

func readModuleBazel(module string) (string, error) {
	path, err := runfiles.Rlocation(module + "/MODULE.bazel")
	if err != nil {
		return "", err
	}

	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	return string(content), nil
}

func parseModuleVersion(content string) (string, error) {
	var moduleFound bool = false
	for _, line := range strings.Split(content, "\n") {
		text := strings.TrimRight(line, "\r")
		if moduleFound {
			if strings.HasSuffix(text, ")") {
				return "", errors.New("Failed to parse version from module section")
			}
			split := strings.SplitN(text, " = ", 2)
			if len(split) < 2 {
				continue
			}
			param, val := split[0], split[1]
			if strings.Trim(param, " ") == "version" {
				return strings.Trim(val, "\" ,"), nil
			}

		} else if strings.HasPrefix(text, "module(") {
			moduleFound = true
			continue
		}
	}
	return "", errors.New("Failed to parse version from MODULE.bazel")
}

func TestVersionFiles(t *testing.T) {
	version, found := os.LookupEnv("VERSION")
	if !found {
		t.Fatal("Couldn't parse VERSION from environment.")
	}

	for _, module := range modules {
		content, err := readModuleBazel(module)
		if err != nil {
			t.Fatalf("Error reading %s/MODULE.bazel: %v", module, err)
		}

		moduleVersion, err := parseModuleVersion(content)
		if err != nil {
			t.Fatalf("Error parsing %s/MODULE.bazel: %v", module, err)
		}

		if version != moduleVersion {
			t.Errorf("version.bzl (%s) != %s/MODULE.bazel (%s)", version, module, moduleVersion)
		}

		if module == "rules_helm" {
			continue
		}

		match := rulesHelmDep.FindStringSubmatch(content)
		if match == nil {
			t.Errorf("%s/MODULE.bazel does not declare a `bazel_dep` on `rules_helm`", module)
			continue
		}

		if version != match[1] {
			t.Errorf("version.bzl (%s) != %s/MODULE.bazel bazel_dep on rules_helm (%s)", version, module, match[1])
		}
	}
}
