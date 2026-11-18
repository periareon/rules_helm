package main

import (
	"bytes"
	"encoding/json"
	"testing"
	"text/template"
)

func TestToJSON(t *testing.T) {
	var buf bytes.Buffer
	input := `{"b": "<a & b>", "a": "x", "n": 12345678901234567890, "f": 1.0}`
	if err := render(&buf, []byte(input), `{{ toJson . }}`); err != nil {
		t.Fatal(err)
	}
	if got, want := buf.String(), `{"a":"x","b":"<a & b>","f":1.0,"n":12345678901234567890}`; got != want {
		t.Errorf("toJson = %s, want %s", got, want)
	}
}

func TestReplace(t *testing.T) {
	var buf bytes.Buffer
	if err := render(&buf, []byte(`{"v": "a-b-c"}`), `{{ .v | replace "-" "+" }}`); err != nil {
		t.Fatal(err)
	}
	if got, want := buf.String(), "a+b+c"; got != want {
		t.Errorf("replace = %q, want %q", got, want)
	}
}

func TestRenderRejectsTrailingData(t *testing.T) {
	var buf bytes.Buffer
	if err := render(&buf, []byte(`{"a": "x"} {}`), `{{ .a }}`); err == nil {
		t.Errorf("render with trailing data = %q, want an error", buf.String())
	}
}

// escapeAnnotations is a copy of `_ESCAPE_ANNOTATIONS` in
// `extensions/img/private/oci_manifest.bzl`. This test shows `toJson` and
// `replace` can escape values only; `//tests/helm_oci_manifest` in
// `rules_helm_img` checks the `.bzl` copy end to end against `helm_oci_digest`.
const escapeAnnotations = `{{ "{" }}{{ $sep := "" }}{{ range $k, $v := . }}{{ $sep }}` +
	`{{ toJson $k }}:{{ $v | replace "{{" "{{\"{{\"}}" | toJson }}` +
	`{{ $sep = "," }}{{ end }}{{ "}" }}`

// TestEscapeAnnotations renders escapeAnnotations, expands each value the way
// `rules_img` does, and expects the original keys and values back.
func TestEscapeAnnotations(t *testing.T) {
	values := map[string]string{
		"empty":          "",
		"plain":          "plain",
		"open":           "{{",
		"close":          "}}",
		"action":         "{{ .Values.x }}",
		"triple":         "{{{",
		"trim":           "{{-",
		"escaped":        `{{"{{"}}`,
		"mixed":          "a {{ b }} c {{",
		"quote":          `quote " and backslash \ {{`,
		"html":           "<html> & {{",
		"key.{{":         "v",
		"key.{{ .x }}":   "{{ y",
		`key."quoted"{{`: "z",
	}
	input, err := json.Marshal(values)
	if err != nil {
		t.Fatal(err)
	}

	var buf bytes.Buffer
	if err := render(&buf, input, escapeAnnotations); err != nil {
		t.Fatal(err)
	}

	escaped := map[string]string{}
	if err := json.Unmarshal(buf.Bytes(), &escaped); err != nil {
		t.Fatalf("output is not a JSON object of strings: %v\n%s", err, buf.String())
	}
	if len(escaped) != len(values) {
		t.Fatalf("output has %d keys, want %d: %s", len(escaped), len(values), buf.String())
	}

	for key, want := range values {
		value, ok := escaped[key]
		if !ok {
			t.Errorf("key %q is missing from the output: %s", key, buf.String())
			continue
		}
		tmpl, err := template.New("expand").Parse(value)
		if err != nil {
			t.Errorf("parsing escaped %q: %v", want, err)
			continue
		}
		var got bytes.Buffer
		if err := tmpl.Execute(&got, map[string]any{}); err != nil {
			t.Errorf("executing escaped %q: %v", want, err)
			continue
		}
		if got.String() != want {
			t.Errorf("expanding escaped %q = %q", want, got.String())
		}
	}
}
