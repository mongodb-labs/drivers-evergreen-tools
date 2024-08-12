# Supporting code for GitHub Apps

## create_or_modify_comment

Uses `mongodb-drivers-pr-bot` to create/update comments on PRs
with the results of an EVG task.  We offer a convenience script to install node,
fetch secrets and run the app:

```bash
bash create_or_modifiy_comment.sh -o "<repo-owner>" -n "<repo-name>" -h "<head-commit-sha>" -m "<comment-match>" -c "<path-to-comment-file>"
```

Note: this script be run on a Linux EVG Host or locally.  It will self-manage the credentials it needs.

## apply-labels

Uses `mongodb-drivers-pr-bot` to apply labels according to [labeler](https://github.com/actions/labeler) config,
without the need for a `pull_request_target` trigger.  Note: only the `changed-files: > any-glob-to-any-file:` config
is currently implemented.

We offer a convenience script to install node,
fetch secrets and run the app:

```bash
bash apply-labels.sh -o "<repo-owner>" -n "<repo-name>" -h "<head-commit-sha>" -l "<path-to-labeler-config>"
```

Note: this script can be run on a Linux EVG Host or locally.  It will self-manage the credentials it needs.

## add-reviewer

Uses `mongodb-drivers-pr-bot` to apply add a random reviewer based on a text file.

We offer a convenience script to install node,
fetch secrets and run the app:

```bash
bash assign-reviewer.sh -o "<repo-owner>" -n "<repo-name>" -h "<head-commit-sha>" -p "<path-to-reviewer-list>"
```

Note: this script can be run on a Linux EVG Host or locally.  It will self-manage the credentials it needs.

## backport-pr

Uses `mongodb-drivers-pr-bot` to backport a PR from one branch to another.  It is triggered by the magic
comment "drivers-pr-bot please backport to {target_branch}".  The script should be run in an EVG task on a merge.
If the matching comment is found, it will attempt to create a new branch and cherry-pick the commit, and then
create a PR with the change.  If the cherry-pick fails, it will create a comment on the PR with the instructions
to make the cherry-pick manually.

If the PR is merged and the task has already run before the magic comment is made, you can make the magic comment
and then manually restart the task to pick up the backport.

The script is called as:

```bash
bash backport-pr.sh {owner} {repo} {target_sha}
```
