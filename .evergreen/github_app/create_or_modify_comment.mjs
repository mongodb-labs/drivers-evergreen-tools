/**
 * Create or modify a GitHub comment using the mongodb-drivers-pr-bot.
 */
import * as fs from "fs";
import * as process from "process";
import { program } from 'commander';
import { getOctokit, findComment } from './utils.mjs';

// Handle cli.
program
  .version('1.0.0', '-v, --version')
  .usage('[OPTIONS]...')
  .requiredOption('-o, --repo-owner <owner>', 'The owner of the repo (e.g. mongodb).')
  .requiredOption('-n, --repo-name <name>', 'The name of the repo (e.g. mongo-go-driver).')
  .requiredOption('-m, --body-match <string>', 'The comment body to match')
  .requiredOption('-c, --comment-path <path>', 'The path to the comment body file')
  .requiredOption('-h, --head-sha <sha>', 'The sha of the head commit')
  .parse(process.argv);

const options = program.opts();
const {
  repoOwner: owner,
  repoName: repo,
  bodyMatch,
  commentPath,
  headSha: targetSha
 } = options;
const bodyText = fs.readFileSync(commentPath, { encoding: 'utf8' });

// Set up the app.
const octokit = await getOctokit(owner);
const headers =  {
    "x-github-api-version": "2022-11-28",
};

// Find a matching comment.
const {comment, issue_number } = await findComment(octokit, owner, repo, targetSha, bodyMatch, "open");
if (!comment) {
    // create comment.
    await octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
        owner,
        repo,
        issue_number,
        body: bodyText,
        headers
    });
} else {
    // update comment.
    await octokit.request("PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}", {
        owner,
        repo,
        body: bodyText,
        comment_id: comment.id,
        headers
    });

}
