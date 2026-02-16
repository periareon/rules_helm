package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
)

func loadStamps(stampFiles ...string) (map[string]string, error) {
	stamps := map[string]string{}

	for _, stampFile := range stampFiles {
		// The files may not be defined
		if len(stampFile) == 0 {
			continue
		}

		content, err := os.ReadFile(stampFile)
		if err != nil {
			return nil, fmt.Errorf("Error reading file %s: %w", stampFile, err)
		}

		for _, line := range strings.Split(string(content), "\n") {
			split := strings.SplitN(line, " ", 2)
			if len(split) < 2 {
				continue
			}
			key, val := split[0], split[1]
			stamps[key] = val
		}
	}

	return stamps, nil
}

func replaceKeyValues(content string, stamps map[string]string) (string, error) {
	for key, value := range stamps {
		replaceKey := fmt.Sprintf("{%s}", key)
		content = strings.ReplaceAll(content, replaceKey, value)
	}

	return content, nil
}

// writeLines writes the given lines to the specified file, with each line separated by a newline.
func writeLines(lines []string, filePath string) error {
	// Create (or overwrite) the file
	file, err := os.Create(filePath)
	if err != nil {
		return fmt.Errorf("failed to create file: %w", err)
	}
	defer file.Close()

	// Create a new buffered writer
	writer := bufio.NewWriter(file)

	// Write each line to the file
	for _, line := range lines {
		_, err := writer.WriteString(line + "\n")
		if err != nil {
			return fmt.Errorf("failed to write line to file: %w", err)
		}
	}

	// Flush any buffered data to the file
	if err := writer.Flush(); err != nil {
		return fmt.Errorf("failed to flush writer: %w", err)
	}

	return nil
}

func main() {
	output := flag.String("output", "", "The output file.")
	stableStatusFile := flag.String("stable_status_file", "", "The path to the stable workspace status file.")
	volatileStatusFile := flag.String("volatile_status_file", "", "The path to the volatile workspace status file.")

	flag.Parse()
	stampableArgs := flag.Args()

	// Collect all stamp values
	stamps, err := loadStamps(*stableStatusFile, *volatileStatusFile)
	if err != nil {
		log.Fatal(err)
	}

	for i, item := range stampableArgs {
		updated, err := replaceKeyValues(item, stamps)
		if err != nil {
			log.Fatal(err)
		}
		stampableArgs[i] = updated
	}

	writeErr := writeLines(stampableArgs, *output)
	if writeErr != nil {
		log.Fatal(writeErr)
	}
}
