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

### Parameters

To use `perfcomp`, you should have an analytics node URI env variable called `PERF_URI_PRIVATE_ENDPOINT`. You can request for it from the devprod performance team.

To run in your project repository, you need to create a [performance context](https://performance-monitoring-and-analysis.server-tig.prod.corp.mongodb.com/contexts) that captures all benchmarks in your project. This needs to be a triage context. Feel free to refer to the [Go Driver context](https://performance-monitoring-and-analysis.server-tig.prod.corp.mongodb.com/context/name/GoDriver%20perf%20task) as a template.

> _If you are creating a triage context for the first time, it may take a few hours for your project's data to be tagged._

You also need the name of the performance task and variant specific to your project. You can do a query in the analytics node `raw_results` collection:

```
db.raw_results.find({
  “info.project”: “<project>”,
  “info.version”: “<random_evergreen_version>"
})
```

and look for the `variant` and `task_name` properties.

### perfcomp CLI

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
  --perf-context string   specify the performance triage context, ex. "GoDriver perf task" (required)
  --project      string   specify the name of an existing Evergreen project, ex. "mongo-go-driver" (required)
  --task         string   specify the evergreen perf task name, ex. "perf" (required)
  --variant      string   specify the perf task variant, ex. "perf" (required)
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
PERF_URI_PRIVATE_ENDPOINT="<perf_uri>" VERSION_ID="<version>" PROJECT="<project>" CONTEXT="<context>" TASK="<task>" VARIANT="<variant>" .evergreen/run-perf-comp.sh
```

If you would like to see a markdown preview of the report, you can also pass in `HEAD_SHA="test"`. This will generate `.evergreen/perfcomp/perf-report.md`.
