package main

import (
	"bufio"
	"log"
	"os"
	"os/exec"

	"github.com/bazelbuild/rules_go/go/runfiles"
	"github.com/periareon/rules_helm/helm/private/helm_utils"
)

func main() {
	argsRlocation := os.Getenv("RULES_HELM_PUSHER_ARGS_FILE")
	if argsRlocation == "" {
		log.Fatalf("RULES_HELM_PUSHER_ARGS_FILE environment variable is not set")
	}

	argsFilePath := helm_utils.GetRunfile(argsRlocation)

	file, err := os.Open(argsFilePath)
	if err != nil {
		log.Fatalf("Failed to open args file %s: %v", argsFilePath, err)
	}
	defer file.Close()

	var imagePushers []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line != "" {
			imagePushers = append(imagePushers, helm_utils.GetRunfile(line))
		}
	}
	if err := scanner.Err(); err != nil {
		log.Fatalf("Failed to read args file: %v", err)
	}

	r, err := runfiles.New()
	if err != nil {
		log.Fatalf("Unable to create runfiles: %v", err)
	}

	for _, pusher := range imagePushers {
		cmd := exec.Command(pusher)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Env = append(os.Environ(), r.Env()...)

		log.Printf("Running image pusher: %s", pusher)
		if err := cmd.Run(); err != nil {
			log.Fatalf("Failed to run image pusher %s: %v", pusher, err)
		}
	}
}
