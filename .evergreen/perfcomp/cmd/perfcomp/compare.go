package main

import (
	"fmt"
	"log"
	"math"
	"os"
	"sort"
	"strings"
	"text/tabwriter"

	"github.com/mongodb-labs/drivers-evergreen-tools/perfcomp"
	"github.com/spf13/cobra"
)

// For support for other projects, a performance context needs to be created and added here.
var projectToPerfContext = map[string]string{
	"mongo-go-driver": "GoDriver perf task",
}

func newCompareCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "compare",
		Short: "compare evergreen patch to mainline commit",
		// Version id is a required argument
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) < 1 {
				return fmt.Errorf("this command requires an evergreen patch version ID")
			}
			return nil
		},
	}

	cmd.Flags().String("project", "mongo-go-driver", "specify the name of an existing Evergreen project")

	cmd.Run = func(cmd *cobra.Command, args []string) {
		// Check for variables
		uri := os.Getenv("PERF_URI_PRIVATE_ENDPOINT")
		if uri == "" {
			log.Fatal("PERF_URI_PRIVATE_ENDPOINT env variable is not set")
		}

		// Retrieve the project flag value
		project, err := cmd.Flags().GetString("project")
		if err != nil {
			log.Fatalf("failed to get project flag: %v", err)
		}

		// Validate the project flag and perf context
		if project == "" {
			log.Fatal("must provide project")
		}
		perfContext, ok := projectToPerfContext[project]
		if !ok {
			log.Fatalf("support for project %q is not configured yet", project)
		}

		if err := runCompare(cmd, args, project, perfContext); err != nil {
			log.Fatalf("failed to compare: %v", err)
		}
	}

	return cmd
}

func createComment(result perfcomp.CompareResult) string {
	var comment strings.Builder
	fmt.Fprintf(&comment, "The following benchmark tests for version %s had statistically significant changes (i.e., |z-score| > 1.96):\n\n", result.Version)

	w := tabwriter.NewWriter(&comment, 0, 0, 1, ' ', 0)
	fmt.Fprintln(w, "| Benchmark\t| Measurement\t| % Change\t| Patch Value\t| Stable Region\t| H-Score\t| Z-Score\t| ")
	fmt.Fprintln(w, "| ---------\t| -----------\t| --------\t| -----------\t| -------------\t| -------\t| -------\t|")

	if len(result.SigEnergyStats) == 0 {
		comment.Reset()
		fmt.Fprintf(&comment, "There were no significant changes to the performance to report for version %s.\n", result.Version)
	} else {
		sort.Slice(result.SigEnergyStats, func(i, j int) bool {
			return math.Abs(result.SigEnergyStats[i].PercentChange) > math.Abs(result.SigEnergyStats[j].PercentChange)
		})
		for _, es := range result.SigEnergyStats {
			fmt.Fprintf(w, "| %s\t| %s\t| %.4f\t| %.4f\t| Avg: %.4f, Med: %.4f, Stdev: %.4f\t| %.4f\t| %.4f\t|\n", es.Benchmark, es.Measurement, es.PercentChange, es.MeasurementVal, es.StableRegion.Mean, es.StableRegion.Median, es.StableRegion.Std, es.HScore, es.ZScore)
		}
	}
	w.Flush()

	comment.WriteString("\n*For a comprehensive view of all microbenchmark results for this PR's commit, please check out the Evergreen perf task for this patch.*")
	return comment.String()

}

func runCompare(cmd *cobra.Command, args []string, project string, perfContext string) error {
	perfAnalyzerConnString := os.Getenv("PERF_URI_PRIVATE_ENDPOINT")
	version := args[len(args)-1]

	res, err := perfcomp.Compare(cmd.Context(), version, perfAnalyzerConnString, project, perfContext)
	if err != nil {
		log.Fatalf("failed to compare: %v", err)
	}
	res.CommitSHA = os.Getenv("HEAD_SHA")
	res.MainlineCommit = os.Getenv("BASE_SHA")

	prComment := createComment(*res)
	log.Println("🧪 Performance Results")
	log.Println(prComment)

	if res.CommitSHA != "" {
		// Write results to .txt file to parse into markdown comment
		fWrite, err := os.Create(perfReportFileTxt)
		if err != nil {
			log.Fatalf("Could not create %s: %v", perfReportFileTxt, err)
		}
		defer fWrite.Close()

		fmt.Fprintf(fWrite, "Version ID: %s\n", version)
		fmt.Fprintf(fWrite, "Commit SHA: %s\n", res.CommitSHA)
		fmt.Fprintln(fWrite, prComment)
		log.Printf("PR commit %s: saved to %s for markdown comment.\n", res.CommitSHA, perfReportFileTxt)
	}

	return nil
}
