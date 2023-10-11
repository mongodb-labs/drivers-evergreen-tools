# Supporting code for GitHub Apps

## Prerequisities

Node 18+

## mongodb-drivers-comment-bot

Use mongodb-drivers-comment-bot to create/update comments on PRs
with the results of an EVG task.  The credentials are retrieved from the AWS 
Secrets Manager.  The target repo and pull request are inferred from the 
source repository checkout.  We offer a convenience script to fetch secrets and
run the app:

```bash
bash create_or_modifiy_comment.sh -s "<path-to-source-repo>" -m "<comment match>" -c "<path-to-comment-file>"
```
