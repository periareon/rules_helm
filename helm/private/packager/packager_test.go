package main

import (
	"strings"
	"testing"
)

func TestImageStampsAliases(t *testing.T) {
	group := imageStamps(ImageInfo{
		Label:      "@@+ext+base//:image_import",
		Aliases:    []string{"@@+ext+base//:image"},
		Repository: "index.docker.io/library/alpine",
		Digest:     "sha256:abc",
		RemoteTag:  "3.23",
	}, false)

	content := strings.Join([]string{
		"{@@@+ext+base//:image}",
		"{@+ext+base//:image.digest}",
		"{@@@+ext+base//:image.registry}",
		"{@@@+ext+base//:image.project}",
		"{@@@+ext+base//:image.tag}",
		"{@@@+ext+base//:image_import.repository}",
	}, "\n")
	got, err := replaceKeyValues(content, []ReplacementGroup{group}, true)
	if err != nil {
		t.Fatal(err)
	}

	want := strings.Join([]string{
		"index.docker.io/library/alpine@sha256:abc",
		"sha256:abc",
		"index.docker.io",
		"library/alpine",
		"3.23",
		"index.docker.io/library/alpine",
	}, "\n")
	if got != want {
		t.Errorf("replaceKeyValues() = %q, want %q", got, want)
	}
}

func TestImageStampsMissingNamesAliases(t *testing.T) {
	group := imageStamps(ImageInfo{
		Label:      "@@+ext+base//:image_import",
		Aliases:    []string{"@@+ext+base//:image"},
		Repository: "index.docker.io/library/alpine",
		Digest:     "sha256:abc",
	}, false)

	_, err := replaceKeyValues("no stamps here", []ReplacementGroup{group}, true)
	if err == nil || !strings.Contains(err.Error(), "@@+ext+base//:image_import or @@+ext+base//:image") {
		t.Errorf("replaceKeyValues() error = %v, want one naming both labels", err)
	}
}
