# Supporting code for GitHub Apps

## mongodb-drivers-comment-bot

Use mongodb-drivers-comment-bot to create/update comments on PRs with the results of an EVG task. We offer a convenience
script to install node, fetch secrets and run the app:

```bash
bash create_or_modifiy_comment.sh -o "<repo-owner>" -n "<repo-name>" -h "<head-commit-sha>" -m "<comment-match>" -c "<path-to-comment-file>"
```
