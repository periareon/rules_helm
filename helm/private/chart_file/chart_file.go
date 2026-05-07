package main

import (
	"flag"
	"log"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type ChartFile struct {
	Name         string             `yaml:"name"`
	Version      string             `yaml:"version"`
	KubeVersion  *string            `yaml:"kubeVersion,omitempty"`
	ApiVersion   string             `yaml:"apiVersion"`
	AppVersion   string             `yaml:"appVersion"`
	Description  *string            `yaml:"description,omitempty"`
	Type         string             `yaml:"type"`
	Keywords     *[]string          `yaml:"keywords,omitempty"`
	Home         *string            `yaml:"home,omitempty"`
	Sources      []string           `yaml:"sources,omitempty"`
	Dependencies *[]*Dependency     `yaml:"dependencies,omitempty"`
	Maintainers  *[]*Maintainer     `yaml:"maintainers,omitempty"`
	Icon         *string            `yaml:"icon,omitempty"`
	Deprecated   *bool              `yaml:"deprecated,omitempty"`
	Annotations  *map[string]string `yaml:"annotations,omitempty"`
}

type Dependency struct {
	Name         string    `yaml:"name"`
	Version      string    `yaml:"version"`
	Repository   string    `yaml:"repository"`
	Condition    *string   `yaml:"condition,omitempty"`
	Tags         *[]string `yaml:"tags,omitempty"`
	Enabled      *bool     `yaml:"enabled,omitempty"`
	ImportValues *[]string `yaml:"import-values,omitempty"`
	Alias        *string   `yaml:"alias,omitempty"`
}

type Maintainer struct {
	Name  *string `yaml:"name"`
	Email *string `yaml:"email,omitempty"`
	Url   *string `yaml:"url,omitempty"`
}

type FileFlag struct {
	Name        string
	regularFlag *string
	fileFlag    *string
}

func NewFileFlag(flagName, defaultValue, usage string) (*FileFlag, error) {
	return &FileFlag{
		Name:        flagName,
		regularFlag: flag.String(flagName, defaultValue, usage),
		fileFlag:    flag.String(flagName+"-file", "", usage+" (file)"),
	}, nil
}

func (f *FileFlag) String() string {
	if *f.fileFlag != "" {
		content, err := os.ReadFile(*f.fileFlag)
		if err != nil {
			log.Fatal(err)
		}
		return strings.TrimSpace(string(content))
	}

	return *f.regularFlag
}

func main() {
	appVersion, err := NewFileFlag("app-version", "0.1.0", "App version")

	if err != nil {
		log.Fatal(err)
	}

	chartVersionFile, err := NewFileFlag("version", "", "Chart version")

	if err != nil {
		log.Fatal(err)
	}

	apiVersion := flag.String("api-version", "v2", "API version")
	description := flag.String("description", "", "Chart description")
	chartName := flag.String("name", "", "Chart name")
	chartType := flag.String("type", "application", "Chart type")
	output := flag.String("output", "", "Output file")

	flag.Parse()

	if *output == "" {
		log.Fatal("Output file is required")
	}

	if *chartName == "" {
		log.Fatal("Chart name is required")
	}

	if *chartType == "" {
		log.Fatal("Chart type is required")
	}

	var descriptionPtr *string
	if *description != "" {
		descriptionPtr = description
	}

	chartFile := &ChartFile{
		Name:        *chartName,
		Version:     chartVersionFile.String(),
		ApiVersion:  *apiVersion,
		AppVersion:  appVersion.String(),
		Description: descriptionPtr,
		Type:        *chartType,
	}

	outFile, err := os.Create(*output)
	if err != nil {
		log.Fatal(err)
	}
	defer func(outFile *os.File) {
		err := outFile.Close()
		if err != nil {
			log.Fatal(err)
		}
	}(outFile)

	encoder := yaml.NewEncoder(outFile)
	defer func(encoder *yaml.Encoder) {
		err := encoder.Close()
		if err != nil {
			log.Fatal(err)
		}
	}(encoder)

	if err := encoder.Encode(chartFile); err != nil {
		log.Fatal(err)
	}
}
