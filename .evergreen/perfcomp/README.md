# perfcomp

**perfcomp** is a performance analyzer on a PR commit basis.

## 📦 Installation

To install the latest version:

```bash
go install github.com/mongodb-labs/drivers-evergreen-tools/perfcomp/cmd/perfcomp@latest  
```

Or build it locally in `bin/perfcomp`:

```bash
bash build.sh
```

## 🔧 Usage

To use `perfcomp`, you should have an analytics node URI env variable called `PERF_URI_PRIVATE_ENDPOINT`. You can request for it from the devprod performance team.

To run in your project repository, you need to create a [performance context](https://performance-monitoring-and-analysis.server-tig.prod.corp.mongodb.com/contexts) that captures all benchmarks in your project. Feel free to refer to the [Go Driver context](https://performance-monitoring-and-analysis.server-tig.prod.corp.mongodb.com/context/name/GoDriver%20perf%20task) as a template. Then, add the context to the `projectToPerfContext` map in `./cmd/perfcomp/compare.go`. You will need to re-run `build.sh` after updating the map.

```bash
perfcomp is a cli that reports stat-sig results between evergreen patches with the mainline commit

Usage:
  perfcomp [command]

Available Commands:
  compare     compare evergreen patch to mainline commit
  mdreport    generates markdown output after run
```

### Commands

#### compare
```bash
compare evergreen patch to mainline commit

Usage:
  perfcomp compare [version_id] [flags]

Flags:
  --project string   specify the name of an existing Evergreen project (required)
```

#### mdreport
```bash
generates markdown output after compare run (must be run after `compare`)

Usage:
  perfcomp mdreport
```

### Run via shell script

Alternatively, you can run the perfcomp shell script. This script will run build and then run `compare`. From the root directory,

```bash
PERF_URI_PRIVATE_ENDPOINT="<perf_uri>" VERSION_ID="<version>" PROJECT="<project>" .evergreen/run-perf-comp.sh
```

If you would like to see a markdown preview of the report, you can also pass in `HEAD_SHA=""`. This will generate `.evergreen/perfcomp/perf-report.md`.
