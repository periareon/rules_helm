package helm_utils

import (
	"bufio"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

// BuildHelmCommand constructs an exec.Cmd to run a Helm command with the specified arguments and plugins directory.
// It takes the path to the Helm executable, a slice of arguments for the Helm command, and the path to the plugins directory.
//
// Parameters:
//   - helmPath: The file path to the Helm executable.
//   - args: A slice of strings representing the arguments to pass to the Helm command.
//   - pluginsDir: The path to the Helm plugins directory, used by Helm to locate additional plugins.
//
// Returns:
//   - exec.Cmd: The constructed command that can be executed to run the Helm command.
//   - error: An error if there is an issue in creating the command.
func BuildHelmCommand(helmPath string, args []string, pluginsDir string) (exec.Cmd, error) {
	// Create a temporary directory with a specified prefix.
	tempDir, err := os.MkdirTemp(os.Getenv("TEST_TMPDIR"), "helm_cmd-")
	if err != nil {
		log.Fatal(err)
	}

	// Generate a fake kubeconfig for more consistent results when building packages
	kubeconfig := filepath.Join(tempDir, ".kubeconfig")
	file, err := os.Create(kubeconfig)
	if err != nil {
		log.Fatal(err)
	}
	if err := file.Chmod(0700); err != nil {
		log.Fatal(err)
	}
	file.Close()

	// Set the HELM_PLUGINS environment variable for plugins directory
	cmd := exec.Command(helmPath, args...)

	env := os.Environ()
	env = append(env, fmt.Sprintf("HELM_PLUGINS=%s", pluginsDir))
	env = append(env, fmt.Sprintf("HELM_CACHE_HOME=%s", filepath.Join(tempDir, "cache")))
	env = append(env, fmt.Sprintf("HELM_CONFIG_HOME=%s", filepath.Join(tempDir, "config")))
	env = append(env, fmt.Sprintf("HELM_DATA_HOME=%s", filepath.Join(tempDir, "data")))
	env = append(env, fmt.Sprintf("HELM_REPOSITORY_CACHE=%s", filepath.Join(tempDir, "repository_cache")))
	env = append(env, fmt.Sprintf("HELM_REPOSITORY_CONFIG=%s", filepath.Join(tempDir, "repositories.yaml")))
	env = append(env, fmt.Sprintf("HELM_REGISTRY_CONFIG=%s", filepath.Join(tempDir, "config.json")))
	env = append(env, fmt.Sprintf("KUBECONFIG=%s", kubeconfig))

	cmd.Env = env

	return *cmd, nil
}

// Commands that run outside of Bazel should be able to access environment
// variables from the host machine.
func SandboxFreeEnv(current []string) []string {

	keysToRemove := []string{
		"HELM_CACHE_HOME",
		"HELM_CONFIG_HOME",
		"HELM_DATA_HOME",
		"HELM_REPOSITORY_CACHE",
		"HELM_REPOSITORY_CONFIG",
		"HELM_REGISTRY_CONFIG",
		"KUBECONFIG",
	}

	// Convert envVars to a map for easier lookup
	currentEnv := make(map[string]string)
	for _, envVar := range current {
		parts := strings.SplitN(envVar, "=", 2)
		if len(parts) == 2 {
			key := parts[0]
			value := parts[1]
			currentEnv[key] = value
		}
	}

	// Convert replacements to a map for easier lookup
	globalEnv := make(map[string]string)
	for _, replacement := range os.Environ() {
		parts := strings.SplitN(replacement, "=", 2)
		if len(parts) == 2 {
			key := parts[0]
			value := parts[1]
			globalEnv[key] = value
		}
	}

	// Process the removal and replacement
	for _, key := range keysToRemove {
		if value, exists := globalEnv[key]; exists {
			// If the key exists in the replacements map, update the original map
			currentEnv[key] = value
		} else {
			// If the key does not exist in the replacements map, delete it
			delete(currentEnv, key)
		}
	}

	newEnv := make([]string, 0, len(currentEnv))
	for key, value := range currentEnv {
		newEnv = append(newEnv, fmt.Sprintf("%s=%s", key, value))
	}

	return newEnv
}

// ArgvWithFile reads a file and returns its content as a slice of command-line arguments.
// Each line in the file is treated as an individual argument, allowing for the construction
// of argument arrays from configuration files or scripts.
//
// Parameters:
//   - filepath: The path to the file containing arguments, with each argument on a separate line.
//
// Returns:
//   - []string: A slice of strings where each entry corresponds to a line in the file (an argument).
//   - error: An error if the file cannot be read or processed.
func ArgvWithFile(filepath string) ([]string, error) {
	file, err := os.Open(filepath)
	if err != nil {
		return nil, fmt.Errorf("failed to open arguments file: %w", err)
	}
	defer file.Close()

	var args []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		args = append(args, scanner.Text())
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("failed to read arguments file: %w", err)
	}

	// Capture command lien arguments as well
	if len(os.Args) > 1 {
		args = append(args, os.Args[1:]...)
	}

	return args, nil
}

// GetRunfile retrieves the path to a runfile given its runfile path relative to the runfiles directory.
// This is commonly used in build/test environments where runfiles (generated or input files)
// are organized in specific directories.
//
// Parameters:
//   - runfile_path: The relative path to the runfile within the runfiles directory.
//
// Returns:
//   - string: The absolute path to the specified runfile, allowing it to be accessed in the file system.
func GetRunfile(runfile_path string) string {

	runfiles, err := runfiles.New()
	if err != nil {
		log.Fatalf("Failed to load runfiles: %v", err)
	}

	// Use the runfiles library to locate files
	runfile, err := runfiles.Rlocation(runfile_path)
	// Check that the file actually exists:
	if _, err := os.Stat(runfile); errors.Is(err, os.ErrNotExist) {
		log.Fatalf("File %s found by runfiles doesn't exist", runfile)
	}
	if err != nil {
		log.Fatalf("When locating file %s, got error %v", runfile, err)
	}

	return runfile
}
