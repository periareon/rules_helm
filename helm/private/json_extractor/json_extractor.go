package main

import (
	"encoding/json"
	"flag"
	"log"
	"os"
	"path"
	"strings"
	"text/template"
)

func main() {
	input := flag.String("input", "", "The path to the json file to process")
	output := flag.String("output", "", "The path where the generated file should be written")
	format := flag.String("template", "", "The template to render using the parsed json")

	flag.Parse()

	content, err := os.ReadFile(*input)
	if err != nil {
		log.Fatal(err)
	}

	parsed := make(map[string]any)
	if err := json.Unmarshal(content, &parsed); err != nil {
		log.Fatal(err)
	}

	if err := os.MkdirAll(path.Dir(*output), 0755); err != nil {
		log.Fatal(err)
	}

	tpl, err := template.New("").Funcs(template.FuncMap{
		"trimPrefix": strings.TrimPrefix,
	}).Parse(*format)
	if err != nil {
		log.Fatal(err)
	}

	w, err := os.Create(*output)
	if err != nil {
		log.Fatal(err)
	}

	defer w.Close()
	if err := tpl.Execute(w, parsed); err != nil {
		log.Fatal(err)
	}
}
