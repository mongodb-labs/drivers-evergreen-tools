import * as process from "process";
import { App } from "octokit";

async function getOctokit(owner) {
    /**
     * Get an octokit client for a given owner name (e.g. mongodb or mongodb-labs).
     */
    const appId = process.env.GITHUB_APP_ID;
    const privateKey = process.env.GITHUB_SECRET_KEY.replace(/\\n/g, '\n');
    if (appId == '' || privateKey == '') {
        console.error("Missing GitHub App auth information");
        process.exit(1)
    }

    const installId = process.env['GITHUB_APP_INSTALL_ID_' + owner.toUpperCase()];
    if (installId == '') {
        console.error(`Missing install id for ${owner}`)
        process.exit(1)
    }
    const app = new App({ appId, privateKey });
    return await app.getInstallationOctokit(installId);
}


async function findComment(octokit, owner, repo, targetSha, bodyMatch, state) {
    /**
     * Find a matching PR comment for a given target sha and match text.
     */
    const headers =  {
        "x-github-api-version": "2022-11-28",
    };
    let resp = await octokit.request("GET /repos/{owner}/{repo}/pulls?per_page=100&state={state}&sort=updated&direction=desc", {
        owner,
        repo,
        state,
        headers
    });
    const issue = resp.data.find(pr => {
        if (state === "open") {
            return pr.head.sha.startsWith(targetSha);
        } else {
            return pr.merge_commit_sha.startsWith(targetSha)
        }
    })
    if (issue == null) {
        console.error(`ERROR: Could not find matching pull request for sha "${targetSha}"`)
        process.exit(1)
    }

    // Find a matching comment if it exists.
    resp = await octokit.request("GET /repos/{owner}/{repo}/issues/{issue_number}/comments", {
        owner,
        repo,
        issue_number: issue.number,
        headers
    });
    return resp.data.find(comment => comment.body.includes(bodyMatch));
}


export { getOctokit,  findComment };
