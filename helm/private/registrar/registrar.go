package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"net/url"
	"os"
	"os/exec"
	"strings"

	"github.com/abrisco/rules_helm/helm/private/helm_utils"
	"github.com/bazelbuild/rules_go/go/runfiles"
)

// Chart represents the structure of Chart.yaml
type Chart struct {
	Version string `yaml:"version"`
}

func getHostFromURL(inputURL string) (string, error) {
	// Replace "oci://" with "https://" so that net/url can parse it
	parsedURL, err := url.Parse(strings.Replace(inputURL, "oci://", "https://", 1))
	if err != nil {
		return "", fmt.Errorf("failed to parse URL: %w", err)
	}
	return parsedURL.Host, nil
}

func runHelm(helmPath string, args []string, pluginsDir string, stdin *string) {
	cmd, err := helm_utils.BuildHelmCommand(helmPath, args, pluginsDir)
	if err != nil {
		log.Fatal(err)
	}

	cmd.Env = helm_utils.SandboxFreeEnv(cmd.Env)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if stdin != nil {
		cmd.Stdin = strings.NewReader(*stdin)
	}

	if err := cmd.Run(); err != nil {
		log.Fatalf("Failed to run helm command: %s", err)
	}
}

func main() {
	// Get the file path for args
	argsRlocation := os.Getenv("RULES_HELM_HELM_PUSH_ARGS_FILE")
	if argsRlocation == "" {
		log.Fatalf("RULES_HELM_HELM_PUSH_ARGS_FILE environment variable is not set")
	}

	argsFilePath := helm_utils.GetRunfile(argsRlocation)

	argv, err := helm_utils.ArgvWithFile(argsFilePath)
	if err != nil {
		log.Fatalf("Error loading command line args: %s", err)
	}

	// Setup flags for helm, chart, registry_url, and image_pushers
	rawHelmPath := flag.String("helm", "", "Path to helm binary")
	rawHelmPluginsPath := flag.String("helm_plugins", "", "The path to helm plugins.")
	rawChartPath := flag.String("chart", "", "Path to Helm .tgz file")
	registryURL := flag.String("registry_url", "", "URL of registry to upload helm chart")
	rawLoginURL := flag.String("login_url", "", "URL of registry to login to.")
	pushCmd := flag.String("push_cmd", "push", "Command to publish helm chart.")
	rawImagePushers := flag.String("image_pushers", "", "Comma-separated list of image pusher executables")

	// Parse command line arguments
	flag.CommandLine.Parse(argv)

	// Check required arguments
	if *rawHelmPath == "" || *rawChartPath == "" || *registryURL == "" {
		log.Fatalf("Missing required arguments: helm, chart, registry_url")
	}

	helmPath := helm_utils.GetRunfile(*rawHelmPath)
	helmPluginsPath := helm_utils.GetRunfile(*rawHelmPluginsPath)
	chartPath := helm_utils.GetRunfile(*rawChartPath)

	var imagePushers []string
	if *rawImagePushers != "" {
		for _, pusher := range strings.Split(*rawImagePushers, ",") {
			imagePushers = append(imagePushers, helm_utils.GetRunfile(pusher))
		}
	}

	// Check for registry login credentials
	helmUser := os.Getenv("HELM_REGISTRY_USERNAME")
	var helmPassword string

	// Try to get the password from HELM_REGISTRY_PASSWORD or HELM_REGISTRY_PASSWORD_FILE
	if pwFile := os.Getenv("HELM_REGISTRY_PASSWORD_FILE"); pwFile != "" {
		// Read the first line from the specified password file
		file, err := os.Open(pwFile)
		if err != nil {
			log.Fatalf("Failed to open password file: %v", err)
		}
		defer file.Close()

		scanner := bufio.NewScanner(file)
		if scanner.Scan() {
			helmPassword = scanner.Text()
		}
		if err := scanner.Err(); err != nil {
			log.Fatalf("Failed to read password file: %v", err)
		}
	} else {
		// Use HELM_REGISTRY_PASSWORD if HELM_REGISTRY_PASSWORD_FILE is not set
		helmPassword = os.Getenv("HELM_REGISTRY_PASSWORD")
	}

	// Proceed with login if both username and password are available
	if helmUser != "" && helmPassword != "" {
		loginUrl := *rawLoginURL

		// If an explicit login url was not set, attempt to parse it from registryURL.
		if loginUrl == "" {
			host, err := getHostFromURL(*registryURL)
			if err == nil {
				loginUrl = host
			}
		}

		log.Printf("Logging into Helm registry `%s`...\n", loginUrl)
		runHelm(helmPath, []string{"registry", "login", "--username", helmUser, "--password-stdin", loginUrl}, helmPluginsPath, &helmPassword)
	} else if helmUser != "" {
		log.Printf("WARNING: A Helm registry username was set but no associated `HELM_REGISTRY_PASSWORD`/`HELM_REGISTRY_PASSWORD_FILE` var was found. Skipping `helm registry login`.")
	} else if helmPassword != "" {
		log.Printf("WARNING: A Helm registry password was set but no associated `HELM_REGISTRY_USERNAME` var was found. Skipping `helm registry login`.")
	}

	r, err := runfiles.New()
	if err != nil {
		log.Fatalf("Unable to create runfiles.")
	}

	// Subprocess image pushers
	for _, pusher := range imagePushers {
		cmd := exec.Command(pusher)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Env = r.Env()

		log.Printf("Running image pusher: %s", pusher)
		if err := cmd.Run(); err != nil {
			log.Fatalf("Failed to run image pusher %s: %v", pusher, err)
		}
	}

	// Subprocess helm push
	log.Printf("Running helm %s...\n", *pushCmd)
	runHelm(helmPath, []string{*pushCmd, chartPath, *registryURL}, helmPluginsPath, nil)
}
