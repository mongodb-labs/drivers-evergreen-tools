/**
 * Apply default GitHub PR labels using the mongodb-drivers-comment-bot.
 */
import * as fs from "fs";
import { parse } from 'yaml';
import * as process from "process";
import { program } from 'commander';
import { App } from "octokit";
import { minimatch } from 'minimatch';

const appId = process.env.GITHUB_APP_ID;
const privateKey = process.env.GITHUB_SECRET_KEY.replace(/\\n/g, '\n');
if (appId == '' || privateKey == '') {
    console.error("Missing GitHub App auth information");
    process.exit(1)
}

// Handle cli.
program
  .version('1.0.0', '-v, --version')
  .usage('[OPTIONS]...')
  .requiredOption('-o, --repo-owner <owner>', 'The owner of the repo (e.g. mongodb).')
  .requiredOption('-n, --repo-name <name>', 'The name of the repo (e.g. mongo-go-driver).')
  .requiredOption('-l, --labeler-path <path>', 'The path to labeler config file')
  .requiredOption('-h, --head-sha <sha>', 'The sha of the head commit')
  .parse(process.argv);

const options = program.opts();
const {
  repoOwner: owner,
  repoName: repo,
  labelerPath,
  headSha: targetSha
 } = options;

// Set up the app.
const installId = process.env['GITHUB_APP_INSTALL_ID_' + owner.toUpperCase()];
if (installId == '') {
    console.error(`Missing install id for ${owner}`)
    process.exit(1)
}
const app = new App({ appId, privateKey });
const octokit = await app.getInstallationOctokit(installId);
const headers =  {
    "x-github-api-version": "2022-11-28",
};

// Find the matching pull request.
console.log("Looking for matching PR...");
let resp = await octokit.request("GET /repos/{owner}/{repo}/pulls?state=open&per_page=100", {
    owner,
    repo,
    headers
});
const issue = resp.data.find(pr => pr.head.sha === targetSha);
if (issue == null) {
    console.error(`ERROR: Could not find matching pull request for sha ${targetSha}`)
    process.exit(1)
}
const { number } = issue;
console.log("Looking for matching PR... done.")

// If there are any labels, bail.
if (issue.labels.length > 0) {
    console.log("PR is already labeled!");
    process.exit(0);
}

// Find out which files have changed.
headers['Accept'] = "application/vnd.github.diff"
resp = await octokit.request("GET /repos/{owner}/{repo}/pulls/{number}", {
    owner,
    repo,
    number,
    headers
});
delete headers['Accept'];

// Get the list of changed files.
const fileNames = [];
for (const line of resp.data.split('\n')) {
    if (line.startsWith('diff --git a/')) {
        let fpath = line.split(' ')[2].slice(2);
        fileNames.push(fpath);
    }
}

// Match against the labeler config.
const labelSet = new Set();
const config = parse(fs.readFileSync(labelerPath, { encoding: 'utf-8'}));
for (let label in config) {
    console.log(label)
    console.log(config[label])
    let patterns = config[label][0]['changed-files'][0]['any-glob-to-any-file'];
    if (!Array.isArray(patterns)) {
        patterns = [patterns];
    }
    console.log(patterns)
    for (let pattern of patterns) {
        const matches = minimatch.match(fileNames, pattern, { matchBase: true });
        if (matches.length > 0) {
            labelSet.add(label);
        }
    }
}

// Apply the appropriate labels.
console.log("Adding labels to PR...");
const labels = Array.from(labelSet)
resp = await octokit.request("POST /repos/{owner}/{repo}/issues/{number}/labels", {
    owner,
    repo,
    number,
    labels,
    headers
});
console.log("Adding labels to PR... done.")
