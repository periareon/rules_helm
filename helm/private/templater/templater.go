package main

import (
	"flag"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/periareon/rules_helm/helm/private/helm_utils"
)

// stringSliceFlag is a custom flag type for collecting multiple values
type stringSliceFlag []string

func (i *stringSliceFlag) String() string {
	return strings.Join(*i, ",")
}

func (i *stringSliceFlag) Set(value string) error {
	*i = append(*i, value)
	return nil
}

type Arguments struct {
	helm        string
	helmPlugins string
	chart       string
	values      stringSliceFlag
	output      string
	helmArgs    []string
}

func makeAbsolutePath(path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatal("Couldn't determine current working directory")
	}
	return filepath.Join(cwd, path)
}

func parseArgs() Arguments {
	var args Arguments

	flag.StringVar(&args.helm, "helm", "", "The path to a helm executable")
	flag.StringVar(&args.helmPlugins, "helm_plugins", "", "The path to a helm plugins directory")
	flag.StringVar(&args.chart, "chart", "", "The path to the helm chart to template.")
	flag.Var(&args.values, "values", "Values files to pass to helm's --values flag.")
	flag.StringVar(&args.output, "output", "", "The output file to write.")
	flag.Parse()
	args.helmArgs = flag.CommandLine.Args()

	return args
}

func main() {
	args := parseArgs()

	log.SetFlags(log.LstdFlags | log.Lshortfile)

	chart := makeAbsolutePath(args.chart)
	helm := makeAbsolutePath(args.helm)
	helmPlugins := makeAbsolutePath(args.helmPlugins)
	output := makeAbsolutePath(args.output)

	helmArgs := []string{"template", chart}
	for _, v := range args.values {
		helmArgs = append(helmArgs, "--values", makeAbsolutePath(v))
	}
	helmArgs = append(helmArgs, args.helmArgs...)
	cmd, err := helm_utils.BuildHelmCommand(helm, helmArgs, helmPlugins)
	if err != nil {
		log.Fatal(err)
	}

	outputFile, err := os.Create(output)
	if err != nil {
		log.Fatal(err)
	}

	cmd.Stdout = outputFile
	cmd.Stderr = os.Stderr

	exitCode := 0
	var cmdError error

	cmdErr := cmd.Run()
	if cmdErr != nil {
		if exitError, ok := cmdErr.(*exec.ExitError); ok {
			if status, ok := exitError.Sys().(syscall.WaitStatus); ok {
				exitCode = status.ExitStatus()
			}
		} else {
			cmdError = cmdErr
			exitCode = 1
		}
	}

	if cmdError != nil {
		log.Fatal(cmdError)
	}

	os.Exit(exitCode)
}
