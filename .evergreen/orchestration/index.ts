// index.ts

import { Command } from 'commander';
import fs from 'fs-extra';
import * as path from 'path';
import psList from 'ps-list';
import spawn from 'cross-spawn';
import * as os from 'os';
import which from 'which';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { randomBytes } from 'crypto';
import { MongoCluster } from 'mongodb-runner';
import * as fsNode from 'fs';
const { S_IRUSR } = fsNode.constants;
import { downloadMongoDb } from '@mongodb-js/mongodb-downloader';
import debug from 'debug';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const HERE = __dirname;
const EVG_PATH = path.resolve(HERE, '..');
const DRIVERS_TOOLS = path.resolve(EVG_PATH, '..');
console.log('DRIVERS_TOOLS IS', DRIVERS_TOOLS);
const PLATFORM = os.platform();
const CACHE_DIR = path.join(DRIVERS_TOOLS, ".local/cache");
const VERSION_LIST_URL = process.env["MONGODB_DOWNLOAD_SOURCE"] || "https://downloads.mongodb.org/full.json";
const TMPDIR = path.join(os.tmpdir(), "drivers-orchestration");
const CRYPT_NAME_MAP: Record<string, string> = {
  win32: 'mongo_crypt_v1.dll',
  darwin: 'mongo_crypt_v1.dylib',
  linux: 'mongo_crypt_v1.so',
};

const URI_TXT = path.join(DRIVERS_TOOLS, 'uri.txt');
const MO_EXPANSION_SH = path.join(DRIVERS_TOOLS, 'mo-expansion.sh');
const MO_EXPANSION_YML = path.join(DRIVERS_TOOLS, 'mo-expansion.yml');

function logInfo(msg: string, ...args: unknown[]) {
  // Simple info logger
  console.log(`INFO: ${msg}`, ...args);
}
function logDebug(msg: string, ...args: unknown[]) {
  // Debug logger, toggle by env
  if (process.env.DEBUG) console.log(`DEBUG: ${msg}`, ...args);
}
function logError(msg: string, ...args: unknown[]) {
  console.error(`ERROR: ${msg}`, ...args);
}

// Options Interface
interface CliOptions {
  verbose?: boolean;
  quiet?: boolean;
  version: string;
  topology: string;
  auth: boolean;
  ssl: boolean;
  localAtlas: boolean;
  orchestrationFile?: string;
  loadBalancer: boolean;
  authAws: boolean;
  skipCryptShared: boolean;
  disableTestCommands: boolean;
  storageEngine?: string;
  requireApiVersion: boolean;
  existingBinariesDir?: string;
  tlsPemKeyFile?: string;
  tlsCaFile?: string;
  arch: string;
  mongoOrchestrationHome: string;
  mongodbBinaries: string;
  tlsCertKeyFile?: string;
}

/**
 * Attempts to locate podman or docker executable. Returns full command to use.
 */
function getDockerCmd(): string | null {
  let dockerPath: string | string[] | null = null;

  // Prefer podman if available
  try {
    dockerPath = which.sync('podman') as string;
    // On Unix-like systems, podman often requires sudo
    if (os.platform() !== 'win32') {
      return `sudo ${dockerPath}`;
    }
    return dockerPath;
  } catch { /* not found */ }

  // Fallback to docker
  try {
    dockerPath = which.sync('docker') as string;
    return dockerPath;
  } catch { /* not found */ }

  // None found
  return null;
}

function normalizePath(filepath: string): string {
  if (PLATFORM !== 'win32') return filepath;
  return filepath.replace(/\\/g, '/');
}

// Run a command helper
function runCommand(cmd: string, exitOnError = true, options: {}) {
  logDebug(`Running command ${cmd}...`);
  const result = spawn.sync(cmd, { shell: true, stdio: 'pipe', ...options });
  if (result.error) {
    logError(result.error.message);
    if (exitOnError) process.exit(result.status ?? 1);
  }
  const stdout = result.stdout?.toString().trim();
  const stderr = result.stderr?.toString().trim();
  if (stdout) logInfo(stdout);
  if (stderr) logError(stderr);
  logDebug(`Running command ${cmd}... done.`);
}

// Shutdown Mongo Orchestration by pid/process name
async function shutdownProc(proc: any) {
  try {
    process.kill(proc.pid, 'SIGTERM');
    logInfo(`Terminated process ${proc.pid} (${proc.name})`);
  } catch (err) {
    logError(`Failed to terminate process ${proc.pid}`, err);
  }
}

function shutdownDocker(docker: string, containerId: string): void {
  let cmd: string;
  if (docker.includes('podman')) {
    cmd = `${docker} rm -f ${containerId}`;
  } else {
    cmd = `${docker} kill ${containerId}`;
  }
  try {
    spawn.sync(cmd, { shell: true, stdio: 'inherit' });
    console.log(`Stopped container: ${containerId}`);
  } catch (err) {
    console.error(`Failed to stop container ${containerId}:`, err);
  }
}


async function startAtlas(opts: CliOptions): Promise<string> {
  const version = opts.version ?? 'latest';

  let image = `mongodb/mongodb-atlas-local:${version}`;
  let dockerCmd = getDockerCmd();

  // Evergreen ECR logic (optional, can be expanded)
  if (process.env.CI && !process.env.GITHUB_ACTION) {
    // You might want to run a setup.sh or similar here
    image = `901841024863.dkr.ecr.us-east-1.amazonaws.com/dockerhub/${image}`;
  }

  let cmd = `${dockerCmd} run --rm -d --name mongodb_atlas_local -p 27017:27017`;

  if (opts.auth) {
    cmd += ' -e MONGODB_INITDB_ROOT_USERNAME=bob';
    cmd += ' -e MONGODB_INITDB_ROOT_PASSWORD=pwd123';
  }

  if (dockerCmd?.includes('podman')) {
    cmd += " --health-cmd '/usr/local/bin/runner healthcheck'";
  }

  cmd += ` -P ${image}`;

  console.log('Starting Atlas Local...');
  console.debug('Using command:', cmd);

  // Start container and save container ID
  let containerId: string;
  try {
    const result = spawn.sync(cmd, { shell: true, encoding: 'utf8' });
    if (result.error) throw result.error;
    if (result.status !== 0) {
        throw new Error(result.stderr);
    }
    containerId = (result.stdout ?? '').trim();
    console.log("Created container", containerId);
  } catch (err) {
    console.log('Failed to start Atlas container:', String(err));
    process.exit(1);
  }

  // Wait for container to become healthy
  console.log('Waiting for container to be healthy...');
  let tries = 0;
  const inspectCmd = `${dockerCmd} inspect -f '{{.State.Health.Status}}' ${containerId}`;
  while (true) {
    let resp = '';
    try {
      const result = spawn.sync(inspectCmd, { shell: true, encoding: 'utf8' });
      if (result.error) throw result.error;
      resp = (result.stdout ?? '').trim();
    } catch (err) {
      resp = '';
    }

    if (resp === 'healthy') break;
    if (tries >= 60) {
      console.error('Timed out waiting for container to become healthy');
      process.exit(1);
    }
    await new Promise(res => setTimeout(res, 1000));
    tries++;
  }
  console.log('Atlas Local container is healthy.');

  // Compose Mongo URI and ping using mongosh
  let uri = 'mongodb://127.0.0.1:27017?directConnection=true';
  if (opts.auth) {
    uri = 'mongodb://bob:pwd123@127.0.0.1:27017?directConnection=true';
  }

  const mongoshPath = path.join(opts.mongodbBinaries, 'mongosh');
  const pingCmd = `${mongoshPath} ${uri} --eval 'db.runCommand({ping:1})'`;
  runCommand(pingCmd, false, {});

  console.log('Atlas Local started.');
  return uri;
}


// Stops running servers and images by name.
async function stop(opts: CliOptions) {
    // Kill by process name.
    const allProcs = await psList();
    for (const proc of allProcs) {
        if (
            proc.name === 'mongod' ||
            proc.name === 'mongos'
        ) {
            await shutdownProc(proc);
        }
    }

    // Kill by image name.
    const docker = getDockerCmd();
    if (!docker) {
        return;
    }
    const cmd = `${docker} ps --format '{{.Image}}\t{{.ID}}'`;
    let response = '';

    try {
        const result = spawn.sync(cmd, { shell: true, encoding: 'utf-8' });
        if (result.error) throw result.error;
        if (result.status !== 0) throw result.stderr;
        response = (result.stdout ?? '').trim();
    } catch (e) {
        console.error('Failed to list running containers:', String(e));
        response = '';
    }
    if (!response) return;

    for (const line of response.split('\n')) {
        console.log("line", line)
        // Sometimes an empty line could sneak in
        if (line.trim() === '') continue;
        const [image, containerId] = line.split('\t');
        if (['mongodb/mongodb-atlas-local', 'mongo'].some(prefix => image.startsWith(prefix))) {
        console.log(`Stopping container for image ${image}...`);
        shutdownDocker(docker, containerId);
        console.log(`Stopped container for image ${image}.`);
        }
    }

}


/**
 * Modify the orchestration config data for use inside a Docker container.
 * - Disables ipv6
 * - Changes bind_ip to listen on all interfaces
 * - Adjusts db/log paths to /tmp for each member/port
 */
export function handleDockerConfig(data: any): void {
  const items: any[] = [];

  // Helper: Recursively traverse the config and collect items that have 'ipv6'
  function traverse(root: any) {
    if (Array.isArray(root)) {
      root.forEach(traverse);
      return;
    }
    if (typeof root !== 'object' || root === null) return;
    if ('ipv6' in root) {
      items.push(root);
      return;
    }
    for (const key in root) {
      if (key === 'routers') continue;
      if (typeof root[key] === 'object') traverse(root[key]);
    }
  }

  traverse(data);

  for (const item of items) {
    item.ipv6 = false;
    item.bind_ip = '0.0.0.0,::1';
    if (item.port) item.dbpath = `/tmp/mongo-${item.port}`;
  }

  // Handle routers section
  if (data.routers) {
    for (const router of data.routers) {
      router.ipv6 = false;
      router.bind_ip = '0.0.0.0,::1';
      if (router.port) router.logpath = `/tmp/mongodb-${router.port}.log`;
    }
  }
}

/**
 * Load and process orchestration config data
 */
function getOrchestrationData(opts: CliOptions): any {
  // 1. Calculate config file name
  let orchestrationFile = opts.orchestrationFile;
  if (!orchestrationFile) {
    let fname = 'basic';
    if (opts.auth) fname = 'auth';
    if (opts.ssl) fname += '-ssl';
    if (opts.loadBalancer) fname += '-load-balancer';
    else if (opts.disableTestCommands) fname = 'disableTestCommands';
    else if (opts.storageEngine) fname = opts.storageEngine;
    orchestrationFile = `${fname}.json`;
  }

  // 2. Build config path
  let topology: str = opts.topology ?? 'standalone';
  if (topology === "standalone") {
    topology = "server";
  }
  const moHome = opts.mongoOrchestrationHome ?? path.join(DRIVERS_TOOLS, '.evergreen', 'orchestration');
  const orchPath = path.join(moHome, 'configs', `${topology}s`, orchestrationFile);
  console.log(`Using orchestration file: ${orchPath}`);

  // 3. Read file
  if (!fs.existsSync(orchPath)) {
    throw new Error(`Orchestration config not found: ${orchPath}`);
  }
  let text = fs.readFileSync(orchPath, 'utf8');

  // 4. TLS replacement logic
  if (opts.tlsPemKeyFile || opts.tlsCaFile) {
    if (!opts.tlsPemKeyFile || !opts.tlsCaFile) {
      throw new Error('You must supply both tlsPemKeyFile and tlsCaFile');
    }
    const base = "ABSOLUTE_PATH_REPLACEMENT_TOKEN/.evergreen/x509gen";
    text = text.replace(`${base}/server.pem`, normalizePath(opts.tlsPemKeyFile));
    text = text.replace(`${base}/ca.pem`, normalizePath(opts.tlsCaFile));
  }

  text = text.replace('ABSOLUTE_PATH_REPLACEMENT_TOKEN', normalizePath(DRIVERS_TOOLS));

  // 5. Parse JSON
  let data: any;
  try {
    data = JSON.parse(text);
  } catch (err) {
    throw new Error(`Failed to parse orchestration data: ${err}`);
  }

  // 6. Required API version handling
  if (opts.requireApiVersion) {
    if (opts.topology === 'replica_set') {
      throw new Error('requireApiVersion is not supported with replica_sets');
    }
    data.requireApiVersion = '1';
  }

  // 7. Optionally handle Docker config
  if (process.env.DOCKER_RUNNING) {
    handleDockerConfig(data);
  }

  return data;
}


function handleProcParams(params: any, args: string[]) {
  let foundEnableTestCommands = false;
  for (const key in params) {
      const value = params[key];
      if (Object.prototype.toString.call(value) === '[object Object]') {
        for (const subkey in params[key]) {
          args.push(`--${key}`)
          args.push(`${subkey}=${params[key][subkey]}`);
          if (subkey === "enableTestCommands") {
            foundEnableTestCommands = true;
          }
        }
      } else if (value === true) {
        args.push(`--${key}`);
      } else if (value !== false) {
        args.push(`--${key}`, `${value}`)
      }
    }
    if (!foundEnableTestCommands) {
      args.push("--setParameter", "enableTestCommands=true")
    }
}

async function createCluster(input: any, opts: CliOptions) {
  const id = randomBytes(12).toString('hex');
  const rsTags: any[] = [];
  const rsArgs: string[][] = [];
  const shardArgs: string[][] = [];
  const mongosArgs: string[][] = [];
  const tmpDir = TMPDIR;
  let secondaries = -1;
  let arbiters = 0;
  const args: string[] = [];
  const roles = [
      {'role': 'userAdminAnyDatabase', 'db': 'admin'},
      {'role': 'clusterAdmin', 'db': 'admin'},
      {'role': 'dbAdminAnyDatabase', 'db': 'admin'},
      {'role': 'readWriteAnyDatabase', 'db': 'admin'},
      {'role': 'restore', 'db': 'admin'},
      {'role': 'backup', 'db': 'admin'}
  ];
  let topology: "standalone" | "replset" | "sharded" = "standalone";
  if (opts.topology === "replica_set") {
    topology = "replset"
  } else if (opts.topology == "sharded_cluster") {
    topology = "sharded"
  }

  // Handle top level options.
  const skipKeys = ["shards", "sslParams", "routers", "login", "password", "id", "name", "procParams"];
  for (const key in input) {
    if (skipKeys.includes(key)) {
      continue;
    }
    const value = input[key];
    if (key === "auth_key") {
      const keyFile = path.join(tmpDir, `key-file-${id}.txt`);
      await fs.writeFile(keyFile, input["auth_key"]);
      args.push("--keyFile", keyFile);
      await fs.chmod(keyFile, S_IRUSR);
    } else if (value === true) {
      args.push(`--${key}`);
    } else if ((value !== false)) {
      args.push(`--${key}`, `${value}`)
    }
  }

  // Handle standalone proc parameters.
  if (topology == "standalone") {
    if ("procParams" in input) {
      handleProcParams(input["procParams"], args);
    }
  }

  // Handle replicaset members.
  if (topology === "replset") {
    args.push("--replSet", input["id"])
    input.members.forEach((member: any) => {
      const memberArgs: string[] = [];
      if ("rsParams" in member && "tags" in member["rsParams"]) {
        rsTags.push(member["rsParams"]["tags"]);
      } else {
        rsTags.push({})
      }
      if ("rsParams" in member && "arbiterOnly" in member["rsParams"]) {
        if (member["rsParams"]["arbiterOnly"]) {
          arbiters += 1;
        } else {
          secondaries += 1;
        }
      } else {
        secondaries += 1;
      }
      if ("procParams" in member) {
        handleProcParams(member["procParams"], memberArgs);
      }
      rsArgs.push(memberArgs);
    })
  }

  // Handle shards and routers.
  if (topology == "sharded" ) {
    input.shards[0].shardParams.members.forEach((member: any) => {
      const memberArgs: string[] = [];
      if ("procParams" in member) {
        handleProcParams(member["procParams"], memberArgs);
      }
      shardArgs.push(memberArgs);
    });
    input.routers.forEach((router: any) => {
      const routerArgs: string[] = [];
      handleProcParams(router, routerArgs);
      mongosArgs.push(routerArgs);
    });
    secondaries = 0;
    arbiters = 0;
  }

  // Handle tls options.
  const clientOptions: any = {};
  if ("sslParams" in input) {
    if (!process.env.MONGO_ORCHESTRATION_HOME) {
      throw new Error("Missing environment variable MONGO_ORCHESTRATION_HOME!")
    }
    if (!process.env.DRIVERS_TOOLS) {
      throw new Error("Missing environment variable DRIVERS_TOOLS!")
    }
    const clientCert = path.join(process.env["MONGO_ORCHESTRATION_HOME"], "lib", "client.pem");
    clientOptions.ssl = true;
    clientOptions.tlsCertificateKeyFile = clientCert;
    clientOptions.tlsAllowInvalidCertificates = true;

    for (const key in input["sslParams"]) {
      let value = input["sslParams"][key];
      if ( String(value).includes("ABSOLUTE_PATH_REPLACEMENT_TOKEN")) {
        value = value.replace("ABSOLUTE_PATH_REPLACEMENT_TOKEN", process.env["DRIVERS_TOOLS"])
      }
      if (value === true) {
        args.push(`--${key}`);
      } else if (value !== false) {
        args.push(`--${key}`, `${value}`)
      }
    }
  }

  // Start the cluster with the desired options.
  const cluster = await MongoCluster.start({
    topology,
    tmpDir,
    binDir: opts.mongodbBinaries,
    args,
    secondaries,
    arbiters,
    rsArgs,
    rsTags,
    shardArgs,
    mongosArgs,
    clientOptions,
    login: input.login,
    password: input.password,
    roles
  });

  // Handle the cluster uri.
  const uri = cluster.connectionString
  console.log("Cluster URI: ", uri);
  await fs.appendFile(MO_EXPANSION_YML, `\nMONGODB_URI: "${uri}"`);
  await fs.appendFile(MO_EXPANSION_SH, `\nMONGODB_URI="${uri}"`);
  await fs.writeFile(URI_TXT, uri);
  await fs.writeFile(path.join(HERE, "server.log"), JSON.stringify(cluster.serialize(), null, 2));
  cluster.unref();

}

async function downloadCryptShared(version: string) {
    // Download crypt_shared.
    // We download crypt_shared to DRIVERS_TOOLS so that it is on a different
    // path location than the other binaries (see spec link).

    // Download crypt_shared.
    const downloadPath = await downloadMongoDb({
        version,
        directory: TMPDIR,
        useLockfile: true,
        downloadOptions: {
            cachePath: CACHE_DIR,
            crypt_shared: true,
            enterprise: true,
            versionListUrl: VERSION_LIST_URL
        }
    });

    const targetFile = CRYPT_NAME_MAP[PLATFORM];
    const targetPath = path.join(DRIVERS_TOOLS, targetFile);
    await fs.copyFile(path.join(downloadPath, targetFile), targetPath);
    const cryptText = `CRYPT_SHARED_LIB_PATH: "${normalizePath(targetPath)}"`;
    console.log("writing expansion file to", MO_EXPANSION_YML);
    await fs.writeFile(MO_EXPANSION_YML, cryptText, "utf8");
    await fs.writeFile(MO_EXPANSION_SH, cryptText.replace(": ", "="), "utf8");
}

// Cleans up files, etc.
function cleanRun(opts: CliOptions) {
  fs.removeSync(opts.mongodbBinaries);
  fs.removeSync(path.join(DRIVERS_TOOLS, 'mongodb'));
  [URI_TXT, MO_EXPANSION_SH, MO_EXPANSION_YML].forEach(file => {
    fs.removeSync(file);
  });
  fs.removeSync(path.join(DRIVERS_TOOLS, CRYPT_NAME_MAP[PLATFORM]));
}

async function downloadBinaries(opts: CliOptions) {
  // Handle the mongod and mongos binaries.
  let binDir = opts.mongodbBinaries;
  let downloadPath: string;
  if (opts.existingBinariesDir) {
    downloadPath = opts.existingBinariesDir;
  } else {
    const downloadPath = await downloadMongoDb({
        version: opts.version,
        directory: TMPDIR,
        useLockfile: true,
        downloadOptions: {
            cachePath: CACHE_DIR,
            enterprise: true,
            arch: opts.arch,
            versionListUrl: VERSION_LIST_URL
        }
    });
    // Copy mongod and mongos to bin dir
    await fs.mkdirpSync(binDir);
    await fs.copyFile(path.join(downloadPath, "mongod"), path.join(binDir, "mongod"));
    await fs.copyFile(path.join(downloadPath, "mongos"),  path.join(binDir, "mongos"));
  }

  return binDir;
}

function setupDebugLogging() {
    debug.enable("mongodb-downloader,mongodb-runner");
    const logFilePath = path.join(__dirname, 'out.log');
    const stream = fs.createWriteStream(logFilePath, { flags: 'w' });

    function stripAnsi(input: unknown) {
        // Matches and removes most ANSI escape codes
        return String(input).replace(
            // eslint-disable-next-line no-control-regex
            /\x1b\[[0-9;]*m/g,
            ''
        );
    }

    // Custom logger function
    function fileLogger(...args: unknown[]): void {
        stream.write(args.map(stripAnsi).join(' ') + '\n');
    }

    debug.log = fileLogger;
}


// Run mongo orchestration.
async function run(opts: CliOptions) {
  logInfo('Starting orchestration');
  setupDebugLogging();
  await stop(opts);
  cleanRun(opts);
  if (opts.skipCryptShared !== true) {
    try {
        downloadCryptShared(opts.version)
    } catch {
        downloadCryptShared("latest")
    }
  }
  // Create a mongosh runner.
  const binDir = opts.mongodbBinaries;
  await fs.mkdirp(binDir);
  await fs.ensureSymlink(path.join(HERE, "node_modules/@mongosh/cli-repl/bin/mongosh.js"), path.join(binDir, "mongosh"), "file");

  if (opts.localAtlas) {
    await startAtlas(opts);
    return;
  }
  await downloadBinaries(opts);
  const data = getOrchestrationData(opts);
  await createCluster(data, opts);
  logInfo('Running orchestration... done.');
}

const program = new Command();
const TOPOLOGIES = ["standalone", "replica_set", "sharded_cluster"];
program
  .name('mongo-orchestration-tool')
  .description('Run mongo-orchestration and launch a deployment');

program.command('run')
  .option('-v, --verbose', 'Verbose', process.env.VERBOSE === 'true')
  .option('--quiet', 'Quiet', process.env.QUIET === 'true')
  .option('--version <version>', 'MongoDB version', process.env.VERSION || 'latest')
  .option('--topology <topology>', `Topology (${TOPOLOGIES.join(', ')})`, process.env.TOPOLOGY || 'standalone')
  .option('--auth', 'Use authentication', process.env.AUTH === "auth")
  .option('--ssl', 'Enable TLS', process.env.SSL !== undefined)
  .option('--local-atlas', 'Use mongodb-atlas-local', process.env.LOCAL_ATLAS !== undefined)
  .option('--orchestration-file <file>', 'Orchestration file', process.env.ORCHESTRATION_FILE)
  .option('--load-balancer', 'Use load balancer', process.env.LOAD_BALANCER !== undefined)
  .option('--auth-aws', 'Use MONGODB-AWS auth', process.env.AUTH_AWS !== undefined)
  .option('--skip-crypt-shared', 'Skip crypt_shared lib', process.env.SKIP_CRYPT_SHARED !== undefined)
  .option('--disable-test-commands', 'Disable test commands', process.env.DISABLE_TEST_COMMANDS !== undefined)
  .option('--storage-engine <engine>', 'Storage engine', process.env.STORAGE_ENGINE || '')
  .option('--require-api-version', 'Set requireApiVersion', process.env.REQUIRE_API_VERSION !== undefined)
  .option('--existing-binaries-dir <dir>', 'Use existing mongodb binaries dir', process.env.EXISTING_BINARIES_DIR)
  .option('--tls-pem-key-file <file>', 'TLS cert/key PEM', process.env.TLS_PEM_KEY_FILE)
  .option('--tls-ca-file <file>', 'TLS CA file', process.env.TLS_CA_FILE)
  .option('--tls-cert-key-file <file>', 'tlsCertificateKeyFile', process.env.TLS_CERT_KEY_FILE)
  .option('--arch <arch>', 'Architecture', process.env.ARCH || process.arch)
  .option('--mongo-orchestration-home <path>', 'Mongo-orchestration home', process.env.MONGO_ORCHESTRATION_HOME || HERE)
  .option('--mongodb-binaries <path>', 'MongoDB binaries path', process.env.MONGODB_BINARIES || path.join(DRIVERS_TOOLS, 'mongodb', 'bin'))
  .action(async (opts) => {
    if (!TOPOLOGIES.includes(opts.topology)) {
        throw new Error("invalid topology")!
    }
    await run(opts as CliOptions);
  });

program.command('stop')
  .action(async (opts) => {
    await stop(opts as CliOptions);
  });

program.parse(process.argv);

if (!process.argv.slice(2).length) {
  program.outputHelp();
}

// Let's make this a new thing going forward - people can continue to use the old tag if they need a transition
// Remove legacy shell - no one is using it
// Require 4.0+ - no one is using 3.6
// Restore the old start-orchestration for mongomirror/mongosync
// Then we can deprecate and move on without breaking everyone

// TODO
// See how this works on Windows - especially with mongosh.
// Test this with pymongo in CI.
