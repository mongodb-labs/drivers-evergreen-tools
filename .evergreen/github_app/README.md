# Supporting code for GitHub Apps

## create_or_modify_comment

Uses `mongodb-drivers-comment-bot` to create/update comments on PRs
with the results of an EVG task.  We offer a convenience script to install node,
fetch secrets and run the app:

```bash
bash create_or_modifiy_comment.sh -o "<repo-owner>" -n "<repo-name>" -h "<head-commit-sha>" -m "<comment-match>" -c "<path-to-comment-file>"
```

Note: this script be run on a Linux EVG Host or locally.  It will self-manage the credentials it needs.

## apply-labels

Uses `mongodb-drivers-comment-bot` to apply labels according to [labeler](https://github.com/actions/labeler) config,
without the need for a `pull_request_target` trigger.

 We offer a convenience script to install node,
fetch secrets and run the app:

```bash
bash apply-labels.sh -o "<repo-owner>" -n "<repo-name>" -h "<head-commit-sha>" -l "<path-to-labeler-config>"
```

Note: this script be run on a Linux EVG Host or locally.  It will self-manage the credentials it needs.
