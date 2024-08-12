/**
 * Look for a cherry-pick target based on a comment in a PR.
 */
import * as fs from "fs";
import * as process from "process";
import { program } from 'commander';
import { getOctokit, findComment } from './utils.mjs';

const BODY_MATCH = "drivers-pr-bot please backport to ";

// Handle cli.
program
  .version('1.0.0', '-v, --version')
  .usage('[OPTIONS]...')
  .requiredOption('-o, --repo-owner <owner>', 'The owner of the repo (e.g. mongodb).')
  .requiredOption('-n, --repo-name <name>', 'The name of the repo (e.g. mongo-go-driver).')
  .requiredOption('-h, --head-sha <sha>', 'The sha of the head commit')
  .parse(process.argv);

const options = program.opts();
const {
  repoOwner: owner,
  repoName: repo,
  headSha: targetSha
 } = options;

// Set up the app.
const octokit = await getOctokit(owner);
const headers =  {
    "x-github-api-version": "2022-11-28",
};

// Find a matching comment.
const comment = await findComment(octokit, owner, repo, targetSha, BODY_MATCH, "closed");
if (!comment) {
    process.exit(0);
}
const target = comment.body.replace(BODY_MATCH, '')
console.log(target);
