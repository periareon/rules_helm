package main

import (
	"os"
	"testing"
)

func mustEnv(t *testing.T, key string) string {
	t.Helper()
	value := os.Getenv(key)
	if value == "" {
		t.Fatalf("%s is not set", key)
	}
	return value
}
