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

type OverrideInfo struct {
	OverrideMainline bool `bson:"override_mainline"`
	BaseOrder        any  `bson:"base_order"`
	Reason           any  `bson:"reason"`
	User             any  `bson:"user"`
}

type Info struct {
	Project      string `bson:"project"`
	Version      string `bson:"version"`
	Variant      string `bson:"variant"`
	Order        int64  `bson:"order"`
	TaskName     string `bson:"task_name"`
	TaskID       string `bson:"task_id"`
	Execution    int64  `bson:"execution"`
	Mainline     bool   `bson:"mainline"`
	OverrideInfo OverrideInfo
	TestName     string         `bson:"test_name"`
	Args         map[string]any `bson:"args"`
}

type Stat struct {
	Name     string  `bson:"name"`
	Val      float64 `bson:"val"`
	Metadata any     `bson:"metadata"`
}

type Rollups struct {
	Stats []Stat
}

type RawData struct {
	Info                 Info
	CreatedAt            any `bson:"created_at"`
	CompletedAt          any `bson:"completed_at"`
	Rollups              Rollups
	FailedRollupAttempts int64 `bson:"failed_rollup_attempts"`
}

type TimeSeriesInfo struct {
	Project     string         `bson:"project"`
	Variant     string         `bson:"variant"`
	Task        string         `bson:"task"`
	Test        string         `bson:"test"`
	Measurement string         `bson:"measurement"`
	Args        map[string]any `bson:"args"`
}

type StableRegion struct {
	TimeSeriesInfo         TimeSeriesInfo
	Start                  any       `bson:"start"`
	End                    any       `bson:"end"`
	Values                 []float64 `bson:"values"`
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
	Contexts               []any     `bson:"contexts"`
}

type EnergyStats struct {
	Project         string
	Benchmark       string
	Measurement     string
	PatchVersion    string
	StableRegion    StableRegion
	MeasurementVal  float64
	PercentChange   float64
	EnergyStatistic float64
	TestStatistic   float64
	HScore          float64
	ZScore          float64
}

type CompareResult struct {
	CommitSHA      string
	MainlineCommit string
	Version        string
	SigEnergyStats []EnergyStats
}

const expandedMetricsDB = "expanded_metrics"
const rawResultsColl = "raw_results"
const stableRegionsColl = "stable_regions"

// Compare will return statistical results for a patch version using the
// stable region defined by the performance analyzer cluster.
func Compare(ctx context.Context, versionID string, perfAnalyzerConnString string, project string, perfContext string) (*CompareResult, error) {

	// Connect to analytics node
	client, err := mongo.Connect(options.Client().ApplyURI(perfAnalyzerConnString))
	if err != nil {
		return nil, fmt.Errorf("Error connecting client: %v", err)
	}

	defer func() { // Defer disconnect client
		err = client.Disconnect(context.Background())
		if err != nil {
			log.Fatalf("Failed to disconnect client: %v", err)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err = client.Ping(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("Error pinging MongoDB Analytics: %v", err)
	}
	log.Println("Successfully connected to MongoDB Analytics node.")

	db := client.Database(expandedMetricsDB)

	// Get raw data, most recent stable region, and calculate energy stats
	findCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	patchRawData, err := findRawData(findCtx, project, versionID, db.Collection(rawResultsColl))
	if err != nil {
		return nil, fmt.Errorf("Error getting raw data: %v", err)
	}

	allEnergyStats, err := getEnergyStatsForAllBenchMarks(findCtx, patchRawData, db.Collection(stableRegionsColl), perfContext)
	if err != nil {
		return nil, fmt.Errorf("Error getting energy statistics: %v", err)
	}

	// Get statistically significant benchmarks
	statSigBenchmarks := getStatSigBenchmarks(allEnergyStats)
	compareResult := CompareResult{
		Version:        versionID,
		SigEnergyStats: statSigBenchmarks,
	}

	return &compareResult, nil
}

func findRawData(ctx context.Context, project string, version string, coll *mongo.Collection) ([]RawData, error) {
	filter := bson.D{
		{"info.project", project},
		{"info.version", version},
		{"info.variant", "perf"},
		{"info.task_name", "perf"},
	}

	cursor, err := coll.Find(ctx, filter)
	if err != nil {
		log.Fatalf(
			"Error retrieving raw data for version %q: %v",
			version,
			err,
		)
	}
	defer func() {
		err = cursor.Close(ctx)
		if err != nil {
			log.Fatalf("Error closing cursor while retrieving raw data for version %q: %v", version, err)
		}
	}()

	log.Printf("Successfully retrieved %d docs from version %s.\n", cursor.RemainingBatchLength(), version)

	var rawData []RawData
	err = cursor.All(ctx, &rawData)
	if err != nil {
		log.Fatalf(
			"Error decoding raw data from version %q: %v",
			version,
			err,
		)
	}

	return rawData, err
}

// Find the most recent stable region of the mainline version for a specific test/measurement
func findLastStableRegion(ctx context.Context, project string, testname string, measurement string, coll *mongo.Collection, perfContext string) (*StableRegion, error) {
	filter := bson.D{
		{"time_series_info.project", project},
		{"time_series_info.variant", "perf"},
		{"time_series_info.task", "perf"},
		{"time_series_info.test", testname},
		{"time_series_info.measurement", measurement},
		{"last", true},
		{"contexts", bson.D{{"$in", bson.A{perfContext}}}}, // TODO (GODRIVER-3102): Refactor perf context for project switching.
	}

	findOptions := options.FindOne().SetSort(bson.D{{"end", -1}})

	var sr *StableRegion
	err := coll.FindOne(ctx, filter, findOptions).Decode(&sr)
	if err != nil {
		return nil, err
	}
	return sr, nil
}

// For a specific test and measurement
func getEnergyStatsForOneBenchmark(ctx context.Context, rd RawData, coll *mongo.Collection, perfContext string) ([]*EnergyStats, error) {
	testname := rd.Info.TestName
	var energyStats []*EnergyStats

	for i := range rd.Rollups.Stats {
		project := rd.Info.Project
		measName := rd.Rollups.Stats[i].Name
		measVal := rd.Rollups.Stats[i].Val

		stableRegion, err := findLastStableRegion(ctx, project, testname, measName, coll, perfContext)
		if err != nil {
			log.Fatalf(
				"Error finding last stable region for test %q, measurement %q: %v",
				testname,
				measName,
				err,
			)
		}

		// The performance analyzer compares the measurement value from the patch to a stable region that succeeds the latest change point.
		// For example, if there were 5 measurements since the last change point, then the stable region is the 5 latest values for the measurement.
		stableRegionVec := mat.NewDense(len(stableRegion.Values), 1, stableRegion.Values)
		measValVec := mat.NewDense(1, 1, []float64{measVal}) // singleton

		estat, tstat, hscore, err := getEnergyStatistics(stableRegionVec, measValVec)
		if err != nil {
			log.Fatalf(
				"Could not calculate energy stats for test %q, measurement %q: %v",
				testname,
				measName,
				err,
			)
		}

		zscore := getZScore(measVal, stableRegion.Mean, stableRegion.Std)
		pChange := getPercentageChange(measVal, stableRegion.Mean)

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

func getEnergyStatsForAllBenchMarks(ctx context.Context, patchRawData []RawData, coll *mongo.Collection, perfContext string) ([]*EnergyStats, error) {
	var allEnergyStats []*EnergyStats
	for _, rd := range patchRawData {
		energyStats, err := getEnergyStatsForOneBenchmark(ctx, rd, coll, perfContext)
		if err != nil {
			log.Fatalf(
				"Could not get energy stats for %q: %v",
				rd.Info.TestName,
				err,
			)
		} else {
			allEnergyStats = append(allEnergyStats, energyStats...)
		}
	}
	return allEnergyStats, nil
}

func getStatSigBenchmarks(energyStats []*EnergyStats) []EnergyStats { // TODO

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
func getEnergyStatistics(x, y *mat.Dense) (float64, float64, float64, error) {
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
		dist, err := getDistance(x, y)
		if err != nil {
			return 0, 0, 0, err
		}
		A = dist / (xrowsf * yrowsf)
	} else {
		A = 0
	}

	var B float64 // E|X-X'|
	if xrowsf > 0 {
		dist, err := getDistance(x, x)
		if err != nil {
			return 0, 0, 0, err
		}
		B = dist / (xrowsf * xrowsf)
	} else {
		B = 0
	}

	var C float64 // E|Y-Y'|
	if yrowsf > 0 {
		dist, err := getDistance(y, y)
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
func getDistance(x, y *mat.Dense) (float64, error) {
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

// Get Z score for result x, compared to mean u and st dev o.
func getZScore(x, mu, sigma float64) float64 {
	if sigma == 0 {
		return math.NaN()
	}
	return (x - mu) / sigma
}

// Get percentage change for result x compared to mean u.
func getPercentageChange(x, mu float64) float64 {
	if mu == 0 {
		return math.NaN()
	}
	return ((x - mu) / mu) * 100
}
