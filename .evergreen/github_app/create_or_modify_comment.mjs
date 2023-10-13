/**
 * Create or modify a GitHub comment using the mongodb-drivers-comment-bot.
 */
import * as fs from "fs";
import * as process from "process";
import { program } from 'commander';
import { App } from "octokit";

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
  .requiredOption('-m, --body-match <string>', 'The comment body to match')
  .requiredOption('-c, --comment-path <path>', 'The path to the comment body file')
  .requiredOption('-h, --head-sha <sha>', 'The sha of the head commit')
  .parse(process.argv);

const options = program.opts();
const { 
  repoOwner: owner,
  bodyMatch,
  commentPath,
  headSha: targetSha
 } = options;
const bodyText = fs.readFileSync(commentPath, { encoding: 'utf8' });

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
const { number: issueNumber } = issue

// Find a matching comment if it exists, and update it.
resp = await octokit.request("GET /repos/{owner}/{repo}/issues/{issue_number}/comments", {
    owner,
    repo,
    issue_number: issueNumber,
    headers
});
const comment = resp.data.find(comment => comment.body.includes(bodyMatch));
if (!comment) {
    // create comment.
    await octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
        owner,
        repo,
        issue_number: issueNumber,
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
