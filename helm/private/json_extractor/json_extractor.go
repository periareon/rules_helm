package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"io"
	"log"
	"os"
	"path"
	"strings"
	"text/template"
)

// toJSON encodes v as compact JSON, without escaping HTML characters or
// adding a trailing newline, so a value comes back as written.
func toJSON(v any) (string, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return "", err
	}
	return strings.TrimSuffix(buf.String(), "\n"), nil
}

// replace takes the string last, as Sprig's `replace` does, so it can end a
// pipeline: `{{ .x | replace "a" "b" }}`.
func replace(old, new, s string) string {
	return strings.ReplaceAll(s, old, new)
}

// render executes format as a Go template against the JSON object in content.
// Numbers are decoded as json.Number, not float64, so `toJson` writes them
// back unchanged.
func render(w io.Writer, content []byte, format string) error {
	dec := json.NewDecoder(bytes.NewReader(content))
	dec.UseNumber()
	parsed := make(map[string]any)
	if err := dec.Decode(&parsed); err != nil {
		return err
	}
	if _, err := dec.Token(); err != io.EOF {
		return errors.New("unexpected data after the JSON object")
	}

	tpl, err := template.New("").Funcs(template.FuncMap{
		"replace":    replace,
		"toJson":     toJSON,
		"trimPrefix": strings.TrimPrefix,
	}).Parse(format)
	if err != nil {
		return err
	}

	return tpl.Execute(w, parsed)
}

func main() {
	input := flag.String("input", "", "The path to the json file to process")
	output := flag.String("output", "", "The path where the generated file should be written")
	format := flag.String("template", "", "The template to render using the parsed json")

	flag.Parse()

	content, err := os.ReadFile(*input)
	if err != nil {
		log.Fatal(err)
	}

	if err := os.MkdirAll(path.Dir(*output), 0755); err != nil {
		log.Fatal(err)
	}

	var buf bytes.Buffer
	if err := render(&buf, content, *format); err != nil {
		log.Fatal(err)
	}

	if err := os.WriteFile(*output, buf.Bytes(), 0644); err != nil {
		log.Fatal(err)
	}
}
