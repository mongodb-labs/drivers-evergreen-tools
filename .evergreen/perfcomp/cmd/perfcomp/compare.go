package main

import (
	"context"
	"fmt"
	"log"
	"math"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/mongodb-labs/drivers-evergreen-tools/perfcomp"
	"github.com/spf13/cobra"
)

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

	var project, task, variant, perfcontext string
	cmd.Flags().StringVar(&project, "project", "", `specify the name of an existing Evergreen project, ex. "mongo-go-driver"`)
	cmd.Flags().StringVar(&perfcontext, "perf-context", "", `specify the performance triage context, ex. "GoDriver perf task"`)
	// TODO(DRIVERS-3264): Use first task / variant of the project by default for perf filtering
	cmd.Flags().StringVar(&task, "task", "", `specify the evergreen performance task name, ex. "perf"`)
	cmd.Flags().StringVar(&variant, "variant", "", `specify the performance variant, ex. "perf"`)

	for _, flag := range []string{"project", "task", "variant", "context"} {
		cmd.MarkFlagRequired(flag)
	}

	cmd.Run = func(cmd *cobra.Command, args []string) {
		// Check for variables
		uri := os.Getenv("PERF_URI_PRIVATE_ENDPOINT")
		if uri == "" {
			log.Fatal("PERF_URI_PRIVATE_ENDPOINT env variable is not set")
		}

		// Validate all flags
		for _, flag := range []string{project, task, variant, perfcontext} {
			if flag == "" {
				log.Fatalf("must provide %s", flag)
			}
		}

		// Run compare function
		err := runCompare(cmd, args,
			perfcomp.WithProject(project),
			perfcomp.WithTask(task),
			perfcomp.WithVariant(variant),
			perfcomp.WithContext(perfcontext),
		)
		if err != nil {
			log.Fatalf("failed to compare: %v", err)
		}
	}

	return cmd
}

func createComment(result perfcomp.CompareResult) string {
	var comment strings.Builder

	if len(result.SigEnergyStats) == 0 {
		comment.Reset()
		fmt.Fprintf(&comment, "There were no significant changes to the performance to report for version %s.\n", result.Version)
	} else {
		fmt.Fprintf(&comment, "The following benchmark tests for version %s had statistically significant changes (i.e., |z-score| > 1.96):\n\n", result.Version)

		w := tabwriter.NewWriter(&comment, 0, 0, 1, ' ', 0)

		fmt.Fprintln(w, "| Benchmark\t| Measurement\t| % Change\t| Patch Value\t| Stable Region\t| H-Score\t| Z-Score\t| ")
		fmt.Fprintln(w, "| ---------\t| -----------\t| --------\t| -----------\t| -------------\t| -------\t| -------\t|")

		sort.Slice(result.SigEnergyStats, func(i, j int) bool {
			return math.Abs(result.SigEnergyStats[i].PercentChange) > math.Abs(result.SigEnergyStats[j].PercentChange)
		})
		for _, es := range result.SigEnergyStats {
			fmt.Fprintf(w, "| %s\t| %s\t| %.4f\t| %.4f\t| Avg: %.4f, Med: %.4f, Stdev: %.4f\t| %.4f\t| %.4f\t|\n",
				es.Benchmark,
				es.Measurement,
				es.PercentChange,
				es.MeasurementVal,
				es.StableRegion.Mean,
				es.StableRegion.Median,
				es.StableRegion.Std,
				es.HScore,
				es.ZScore,
			)
		}

		w.Flush()
	}

	comment.WriteString("\n*For a comprehensive view of all microbenchmark results for this PR's commit, please check out the Evergreen perf task for this patch.*")
	return comment.String()

}

func runCompare(cmd *cobra.Command, args []string, opts ...perfcomp.CompareOption) error {
	perfAnalyticsConnString := os.Getenv("PERF_URI_PRIVATE_ENDPOINT")
	version := args[len(args)-1]
	opts = append(opts, perfcomp.WithVersion(version))

	ctx, cancel := context.WithTimeout(cmd.Context(), 5*time.Second)
	defer cancel()

	res, err := perfcomp.Compare(ctx, perfAnalyticsConnString, opts...)
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
