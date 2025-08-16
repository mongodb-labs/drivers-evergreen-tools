package main

import (
	"log"

	"github.com/spf13/cobra"
)

func main() {
	cmd := &cobra.Command{
		Use:     "perfcomp",
		Short:   "perfcomp is a cli that reports stat-sig results between evergreen patches with the mainline commit",
		Version: "0.0.0-alpha",
	}

	cmd.AddCommand(newCompareCommand())
	cmd.AddCommand(newMdCommand())

	if err := cmd.Execute(); err != nil {
		log.Fatalf("error: %v", err)
	}
}
