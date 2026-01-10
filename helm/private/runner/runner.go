package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"syscall"

	"github.com/periareon/rules_helm/helm/private/helm_utils"
)

func parseArgsUpToDashDash(argv []string) ([]string, []string) {
	var before, after []string
	foundSeparator := false

	for _, arg := range argv {
		if foundSeparator == false && arg == "--" {
			foundSeparator = true
			continue // Skip adding "--" itself to either list
		}
		if foundSeparator {
			after = append(after, arg)
		} else {
			before = append(before, arg)
		}
	}
	return before, after
}

// ParseHelmOutput extracts sections of Helm output and maps them to their respective sources.
func parseHelmOutput(input string) map[string]string {
	result := make(map[string]string)
	sections := strings.Split(input, "---")
	sourceRegex := regexp.MustCompile(`(?m)^# Source: (.+)$`)

	for _, section := range sections {
		section = strings.TrimSpace(section)
		if section == "" {
			continue
		}

		matches := sourceRegex.FindStringSubmatch(section)
		if len(matches) > 1 {
			source := matches[1]
			content := strings.TrimSpace(strings.Replace(section, matches[0], "", 1))
			result[source] = content
		}
	}

	return result
}

func loadTemplatePatterns(path string) (map[string][]string, error) {
	var data map[string][]string

	file, err := os.Open(path)
	if err != nil {
		return data, fmt.Errorf("Error opening json file: %w", err)
	}
	// Ensure file gets closed when done
	defer file.Close()

	// Decode the JSON file into the struct
	decoder := json.NewDecoder(file)
	if err := decoder.Decode(&data); err != nil {
		return data, fmt.Errorf("Error decoding JSON: %w", err)
	}

	return data, nil
}

func main() {
	// Get the file path for args
	argsRlocation := os.Getenv("RULES_HELM_HELM_RUNNER_ARGS_FILE")
	if argsRlocation == "" {
		log.Fatalf("RULES_HELM_HELM_RUNNER_ARGS_FILE environment variable is not set")
	}

	argsFilePath := helm_utils.GetRunfile(argsRlocation)

	// Read args from the file
	argv, err := helm_utils.ArgvWithFile(argsFilePath)
	if err != nil {
		log.Fatalf("Error loading command line args: %s", err)
	}

	internalArgs, helmArgs := parseArgsUpToDashDash(argv)

	// Setup flags for helm, chart, registry_url, and image_pushers
	rawHelmPath := flag.String("helm", "", "Path to helm binary")
	rawHelmPluginsPath := flag.String("helm_plugins", "", "The path to helm plugins.")
	rawChartPath := flag.String("chart", "", "Path to Helm .tgz file")
	rawImagePushers := flag.String("image_pushers", "", "Comma-separated list of image pusher executables")

	// Parse command line arguments
	flag.CommandLine.Parse(internalArgs)

	_, is_test := os.LookupEnv("RULES_HELM_HELM_TEMPLATE_TEST")
	_, is_debug := os.LookupEnv("RULES_HELM_DEBUG")

	// force template when testing and check in uninstall
	is_uninstall := false
	for _, item := range helmArgs {
		is_uninstall = is_uninstall || item == "uninstall"
		if is_test {
			if item == "install" || item == "upgrade" {
				item = "template"
			}
		}
	}

	// Check required arguments
	if *rawHelmPath == "" || *rawHelmPluginsPath == "" || (!is_uninstall && *rawChartPath == "") {
		log.Fatalf("Missing required arguments: helm, helm_plugins or chart")
	}

	helmPath := helm_utils.GetRunfile(*rawHelmPath)
	helmPluginsPath := helm_utils.GetRunfile(*rawHelmPluginsPath)

	// Update the chart path whenever it's found.
	if *rawChartPath != "" {
		chartPath := helm_utils.GetRunfile(*rawChartPath)
		for i, item := range helmArgs {
			helmArgs[i] = strings.ReplaceAll(item, *rawChartPath, chartPath)
		}
	}

	var imagePushers []string
	if *rawImagePushers != "" {
		for _, pusher := range strings.Split(*rawImagePushers, ",") {
			imagePushers = append(imagePushers, helm_utils.GetRunfile(pusher))
		}
	}

	// Subprocess image pushers
	if !is_test {
		for _, pusher := range imagePushers {
			cmd := exec.Command(pusher)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr

			if err := cmd.Run(); err != nil {
				log.Fatalf("Failed to run image pusher %s: %v", pusher, err)
			}
		}
	}

	cmd, err := helm_utils.BuildHelmCommand(helmPath, helmArgs, helmPluginsPath)
	if err != nil {
		log.Fatal(err)
	}

	var test_stream bytes.Buffer

	if is_test {
		cmd.Stdout = &test_stream
		cmd.Stderr = &test_stream
	} else {
		cmd.Env = helm_utils.SandboxFreeEnv(cmd.Env)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	}

	if is_debug {
		log.Println(strings.Join(cmd.Args, " "))
	}

	var exitCode int = 0
	var cmdError error = nil

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

	// Perform any regex pattern checks requested.
	if is_test {
		fmt.Print(test_stream.String())

		patternsVar, exists := os.LookupEnv("RULES_HELM_HELM_TEMPLATE_TEST_PATTERNS")
		if exists {
			patternsFile := helm_utils.GetRunfile(patternsVar)
			patterns, err := loadTemplatePatterns(patternsFile)
			if err != nil {
				log.Fatal(err)
			}

			templates := parseHelmOutput(test_stream.String())
			failed := false
			for templatePath, testPatterns := range patterns {
				content, found := templates[templatePath]
				if !found {
					failed = true
					log.Printf("Template not found in the helm chart: %s", templatePath)
					continue
				}

				for _, pattern := range testPatterns {
					regex, err := regexp.Compile(pattern)
					if err != nil {
						failed = true
						log.Print("Error compiling regex:", err)
						continue
					}

					if !regex.MatchString(content) {
						failed = true
						log.Printf("Error: The file `%s` does not contain the pattern:\n```\n%s\n```", templatePath, pattern)
						continue
					}
				}
			}

			if failed {
				log.Fatalf("Failed")
			}
		}
	}

	os.Exit(exitCode)
}
