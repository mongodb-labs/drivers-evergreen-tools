package perfcomp

import (
	"context"
	"fmt"
	"log"
	"math"
	"time"

	"go.mongodb.org/mongo-driver/v2/bson"
	"go.mongodb.org/mongo-driver/v2/mongo"
	"go.mongodb.org/mongo-driver/v2/mongo/options"
	"gonum.org/v1/gonum/mat"
)

// RawData defines the shape of the data in the raw_results collection.
// raw_results stores results by benchmark, which holds the values of all its measurements.
// A single measurement from a single benchmark is called a microbenchmark.
type RawData struct {
	Info                 Info
	CreatedAt            any     `bson:"created_at"`
	CompletedAt          any     `bson:"completed_at"`
	Rollups              Rollups // List of all measurement results
	FailedRollupAttempts int64   `bson:"failed_rollup_attempts"`
}

type Info struct {
	Project      string `bson:"project"`
	Version      string `bson:"version"` // Evergreen version that produced the results
	Variant      string `bson:"variant"`
	Order        int64  `bson:"order"`
	TaskName     string `bson:"task_name"`
	TaskID       string `bson:"task_id"`
	Execution    int64  `bson:"execution"`
	Mainline     bool   `bson:"mainline"`
	OverrideInfo OverrideInfo
	TestName     string         `bson:"test_name"` // Benchmark name
	Args         map[string]any `bson:"args"`
}

type OverrideInfo struct {
	OverrideMainline bool `bson:"override_mainline"`
	BaseOrder        any  `bson:"base_order"`
	Reason           any  `bson:"reason"`
	User             any  `bson:"user"`
}

type Rollups struct {
	Stats []Stat
}

type Stat struct {
	Name     string  `bson:"name"` // Measurement name
	Val      float64 `bson:"val"`  // Microbenchmark result
	Metadata any     `bson:"metadata"`
}

// StableRegion defines the shape of the data in the stable_regions collection.
// A stable region is a group of consecutive microbenchmark values between two change points.
type StableRegion struct {
	TimeSeriesInfo         TimeSeriesInfo
	Start                  any       `bson:"start"`
	End                    any       `bson:"end"`
	Values                 []float64 `bson:"values"` // All microbenchmark values that make up the stable region
	StartOrder             int64     `bson:"start_order"`
	EndOrder               int64     `bson:"end_order"`
	Mean                   float64   `bson:"mean"`
	Std                    float64   `bson:"std"`
	Median                 float64   `bson:"median"`
	Max                    float64   `bson:"max"`
	Min                    float64   `bson:"min"`
	CoefficientOfVariation float64   `bson:"coefficient_of_variation"`
	LastSuccessfulUpdate   any       `bson:"last_successful_update"`
	Last                   bool      `bson:"last"`
	Contexts               []any     `bson:"contexts"` // Performance context (e.g. "Go Driver perf comp")
}

type TimeSeriesInfo struct {
	Project     string         `bson:"project"`
	Variant     string         `bson:"variant"`
	Task        string         `bson:"task"`
	Test        string         `bson:"test"`        // Benchmark name
	Measurement string         `bson:"measurement"` // Measurement name
	Args        map[string]any `bson:"args"`
}

// EnergyStats stores the calculated energy statistics for a patch version's specific
// microbenchmark compared to the mainline's stable region for that same microbenchmark.
type EnergyStats struct {
	Project         string
	Benchmark       string
	Measurement     string
	PatchVersion    string       // Evergreen version that produced the results
	StableRegion    StableRegion // Latest stable region from the mainline this patch is comparing against
	MeasurementVal  float64      // Microbenchmark result of the patch version
	PercentChange   float64
	EnergyStatistic float64
	TestStatistic   float64
	HScore          float64
	ZScore          float64
}

// CompareResult is the collection of the energy statistics of all microbenchmarks with
// statistically significant changes for this patch.
type CompareResult struct {
	CommitSHA      string // Head commit SHA
	MainlineCommit string // Base commit SHA
	Version        string // Evergreen patch version
	SigEnergyStats []EnergyStats
}

// Performance analytics node db and collection names
const expandedMetricsDB = "expanded_metrics"
const rawResultsColl = "raw_results"
const stableRegionsColl = "stable_regions"

// CompareOptions stores the information for each project to use as filters.
type CompareOptions struct {
	Project     string // Required
	PerfContext string // Required
	Task        string // Required
	Variant     string // Required
	Version     string // Required
}

type CompareOption func(*CompareOptions)

// WithProject sets the evergreen project on the CompareOptions, for example "mongo-go-driver".
func WithProject(project string) CompareOption {
	return func(opts *CompareOptions) {
		opts.Project = project
	}
}

// WithContext sets the performance triage context on the CompareOptions, for example "GoDriver perf task".
func WithContext(context string) CompareOption {
	return func(opts *CompareOptions) {
		opts.PerfContext = context
	}
}

// WithTask sets the evergreen performance task on the CompareOptions, for example "perf".
func WithTask(task string) CompareOption {
	return func(opts *CompareOptions) {
		opts.Task = task
	}
}

// WithTask sets the performance task variant on the CompareOptions, for example "perf".
func WithVariant(variant string) CompareOption {
	return func(opts *CompareOptions) {
		opts.Variant = variant
	}
}

// WithVersion sets the evergreen version on the CompareOptions, for example "688a39d27d916e0007cf8723".
func WithVersion(version string) CompareOption {
	return func(opts *CompareOptions) {
		opts.Version = version
	}
}

func validateOptions(copts CompareOptions) error {
	if copts.Project == "" {
		return fmt.Errorf("project is required")
	}
	if copts.PerfContext == "" {
		return fmt.Errorf("context is required")
	}
	if copts.Task == "" {
		return fmt.Errorf("task is required")
	}
	if copts.Variant == "" {
		return fmt.Errorf("variant is required")
	}
	if copts.Version == "" {
		return fmt.Errorf("version is required")
	}
	return nil
}

// GetDefaultTaskAndVariant will find the default task and/or variant for a given project
// using the most recent result in the raw_results collection.
func GetDefaultTaskAndVariant(perfAnalyticsConnString, project, task, variant string) (string, string, error) {
	// Connect to analytics node
	client, err := mongo.Connect(options.Client().ApplyURI(perfAnalyticsConnString))
	if err != nil {
		return "", "", fmt.Errorf("error connecting client: %v", err)
	}

	fmt.Println("Successfully connected to MongoDB")

	defer func() { // Defer disconnect client
		err = client.Disconnect(context.Background())
		if err != nil {
			log.Fatalf("failed to disconnect client: %v", err)
		}
	}()

	// Reference the collection in the database
	collection := client.Database(expandedMetricsDB).Collection(rawResultsColl)

	// Build filter for querying raw_results
	filter := bson.M{
		"info.project": project,
	}
	if task != "" {
		filter["info.task_name"] = task
	}
	if variant != "" {
		filter["info.variant"] = variant
	}

	// Set sort options for the query
	opts := options.FindOne().SetSort(bson.D{{Key: "created_at", Value: -1}}) // Sort by latest date

	// Execute the query
	var result RawData
	findCtx, findCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer findCancel()

	err = collection.FindOne(findCtx, filter, opts).Decode(&result)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			fmt.Printf("No matching raw results found for project: %s\n", project)
			return "", "", fmt.Errorf("no matching raw results found for project: %s", project)
		}
		fmt.Printf("Failed to fetch defaults for project %s. Error: %v\n", project, err)
		return "", "", fmt.Errorf("failed to fetch defaults for project %s: %v", project, err)
	}

	// Return the extracted values
	return result.Info.TaskName, result.Info.Variant, nil
}

// Compare will return statistical results for a patch version using the
// stable region defined by the performance analytics cluster.
func Compare(ctx context.Context, perfAnalyticsConnString string, opts ...CompareOption) (*CompareResult, error) {
	copts := &CompareOptions{}
	for _, fn := range opts {
		fn(copts)
	}

	if err := validateOptions(*copts); err != nil {
		return nil, fmt.Errorf("invalid configuration: %w", err)
	}

	// Connect to analytics node
	client, err := mongo.Connect(options.Client().ApplyURI(perfAnalyticsConnString))
	if err != nil {
		return nil, fmt.Errorf("error connecting client: %v", err)
	}

	defer func() { // Defer disconnect client
		err = client.Disconnect(context.Background())
		if err != nil {
			log.Fatalf("failed to disconnect client: %v", err)
		}
	}()

	err = client.Ping(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("error pinging MongoDB Analytics: %v", err)
	}
	log.Println("Successfully connected to MongoDB Analytics node.")

	db := client.Database(expandedMetricsDB)

	// Get raw data, most recent stable region, and calculate energy stats
	findCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	patchRawData, err := findRawData(findCtx, db.Collection(rawResultsColl), copts)
	if err != nil {
		return nil, fmt.Errorf("error getting raw data: %v", err)
	}

	allEnergyStats, err := getEnergyStatsForAllBenchmarks(findCtx, patchRawData, db.Collection(stableRegionsColl), copts)
	if err != nil {
		return nil, fmt.Errorf("error getting energy statistics: %v", err)
	}

	// Get statistically significant benchmarks
	statSigBenchmarks := getStatSigBenchmarks(allEnergyStats)
	compareResult := CompareResult{
		Version:        copts.Version,
		SigEnergyStats: statSigBenchmarks,
	}

	return &compareResult, nil
}

// Gets all raw benchmark data for a specific Evergreen version.
func findRawData(ctx context.Context, coll *mongo.Collection, copts *CompareOptions) ([]RawData, error) {
	// TODO: By default get the first task/variant of the project's raw results and use that for filtering.
	filter := bson.D{
		{"info.project", copts.Project},
		{"info.version", copts.Version},
		{"info.variant", copts.Variant},
		{"info.task_name", copts.Task},
	}

	cursor, err := coll.Find(ctx, filter)
	if err != nil {
		return nil, fmt.Errorf(
			"error retrieving raw data for version %q: %v",
			copts.Version,
			err,
		)
	}
	defer func() {
		err = cursor.Close(ctx)
		if err != nil {
			log.Fatalf("error closing cursor while retrieving raw data for version %q: %v", copts.Version, err)
		}
	}()

	var rawData []RawData
	err = cursor.All(ctx, &rawData)
	if err != nil {
		return nil, fmt.Errorf(
			"error decoding raw data from version %q: %v",
			copts.Version,
			err,
		)
	}
	log.Printf("Successfully retrieved %d docs from version %s.\n", len(rawData), copts.Version)
	return rawData, err
}

// Finds the most recent stable region of the mainline version for a specific microbenchmark.
func findLastStableRegion(ctx context.Context, testname string, measurement string, coll *mongo.Collection, copts *CompareOptions) (*StableRegion, error) {
	filter := bson.D{
		{"time_series_info.project", copts.Project},
		{"time_series_info.variant", copts.Variant},
		{"time_series_info.task", copts.Task},
		{"time_series_info.test", testname},
		{"time_series_info.measurement", measurement},
		{"last", true},
		{"contexts", bson.D{{"$in", bson.A{copts.PerfContext}}}},
	}

	findOptions := options.FindOne().SetSort(bson.D{{"end", -1}})

	var sr StableRegion
	err := coll.FindOne(ctx, filter, findOptions).Decode(&sr)
	if err != nil {
		return nil, err
	}
	return &sr, nil
}

// Calculate the energy statistics for all measurements in a benchmark.
func getEnergyStatsForOneBenchmark(ctx context.Context, rd RawData, coll *mongo.Collection, copts *CompareOptions) ([]*EnergyStats, error) {
	testname := rd.Info.TestName
	var energyStats []*EnergyStats

	for i := range rd.Rollups.Stats {
		project := rd.Info.Project
		measName := rd.Rollups.Stats[i].Name
		measVal := rd.Rollups.Stats[i].Val

		stableRegion, err := findLastStableRegion(ctx, testname, measName, coll, copts)
		if err != nil {
			return nil, fmt.Errorf(
				"error finding last stable region for test %q, measurement %q: %v",
				testname,
				measName,
				err,
			)
		}

		// The performance analyzer compares the measurement value from the patch to a stable region that succeeds the latest change point.
		// For example, if there were 5 measurements since the last change point, then the stable region is the 5 latest values for the measurement.
		stableRegionVec := mat.NewDense(len(stableRegion.Values), 1, stableRegion.Values)
		measValVec := mat.NewDense(1, 1, []float64{measVal}) // singleton

		estat, tstat, hscore, err := calcEnergyStatistics(stableRegionVec, measValVec)
		if err != nil {
			return nil, fmt.Errorf(
				"could not calculate energy stats for test %q, measurement %q: %v",
				testname,
				measName,
				err,
			)
		}

		zscore := calcZScore(measVal, stableRegion.Mean, stableRegion.Std)
		pChange := calcPercentChange(measVal, stableRegion.Mean)

		es := EnergyStats{
			Project:         project,
			Benchmark:       testname,
			Measurement:     measName,
			PatchVersion:    rd.Info.Version,
			StableRegion:    *stableRegion,
			MeasurementVal:  measVal,
			PercentChange:   pChange,
			EnergyStatistic: estat,
			TestStatistic:   tstat,
			HScore:          hscore,
			ZScore:          zscore,
		}
		energyStats = append(energyStats, &es)
	}

	return energyStats, nil
}

func getEnergyStatsForAllBenchmarks(ctx context.Context, patchRawData []RawData, coll *mongo.Collection, copts *CompareOptions) ([]*EnergyStats, error) {
	var allEnergyStats []*EnergyStats
	for _, rd := range patchRawData {
		energyStats, err := getEnergyStatsForOneBenchmark(ctx, rd, coll, copts)
		if err != nil {
			return nil, fmt.Errorf(
				"could not get energy stats for %q: %v",
				rd.Info.TestName,
				err,
			)
		} else {
			allEnergyStats = append(allEnergyStats, energyStats...)
		}
	}
	return allEnergyStats, nil
}

func getStatSigBenchmarks(energyStats []*EnergyStats) []EnergyStats {

	var significantEnergyStats []EnergyStats
	for _, es := range energyStats {
		// The "iterations" measurement is the number of iterations that the Go
		// benchmark suite had to run to converge on a benchmark measurement. It
		// is not comparable between benchmark runs, so is not a useful
		// measurement to print here. Omit it.
		if es.Measurement != "iterations" && math.Abs(es.ZScore) > 1.96 {
			significantEnergyStats = append(significantEnergyStats, *es)
		}
	}

	return significantEnergyStats
}

// Given two matrices, this function returns
// (e, t, h) = (E-statistic, test statistic, e-coefficient of inhomogeneity)
func calcEnergyStatistics(x, y *mat.Dense) (float64, float64, float64, error) {
	xrows, xcols := x.Dims()
	yrows, ycols := y.Dims()

	if xcols != ycols {
		return 0, 0, 0, fmt.Errorf("both inputs must have the same number of columns")
	}
	if xrows == 0 || yrows == 0 {
		return 0, 0, 0, fmt.Errorf("inputs cannot be empty")
	}

	xrowsf := float64(xrows)
	yrowsf := float64(yrows)

	var A float64 // E|X-Y|
	if xrowsf > 0 && yrowsf > 0 {
		dist, err := calcDistance(x, y)
		if err != nil {
			return 0, 0, 0, err
		}
		A = dist / (xrowsf * yrowsf)
	} else {
		A = 0
	}

	var B float64 // E|X-X'|
	if xrowsf > 0 {
		dist, err := calcDistance(x, x)
		if err != nil {
			return 0, 0, 0, err
		}
		B = dist / (xrowsf * xrowsf)
	} else {
		B = 0
	}

	var C float64 // E|Y-Y'|
	if yrowsf > 0 {
		dist, err := calcDistance(y, y)
		if err != nil {
			return 0, 0, 0, err
		}
		C = dist / (yrowsf * yrowsf)
	} else {
		C = 0
	}

	E := 2*A - B - C // D^2(F_x, F_y)
	T := ((xrowsf * yrowsf) / (xrowsf + yrowsf)) * E
	var H float64
	if A > 0 {
		H = E / (2 * A)
	} else {
		H = 0
	}
	return E, T, H, nil
}

// Given two vectors (expected 1 col),
// this function returns the sum of distances between each pair.
func calcDistance(x, y *mat.Dense) (float64, error) {
	xrows, xcols := x.Dims()
	yrows, ycols := y.Dims()

	if xcols != 1 || ycols != 1 {
		return 0, fmt.Errorf("both inputs must be column vectors")
	}

	var sum float64

	for i := 0; i < xrows; i++ {
		for j := 0; j < yrows; j++ {
			sum += math.Abs(x.At(i, 0) - y.At(j, 0))
		}
	}
	return sum, nil
}

// Calculate the Z score for result x, compared to mean mu and st dev sigma.
func calcZScore(x, mu, sigma float64) float64 {
	if sigma == 0 {
		return math.NaN()
	}
	return (x - mu) / sigma
}

// Calculate the percentage change for result x compared to mean mu.
func calcPercentChange(x, mu float64) float64 {
	if mu == 0 {
		return math.NaN()
	}
	return ((x - mu) / mu) * 100
}
