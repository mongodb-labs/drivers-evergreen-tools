#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
pushd $SCRIPT_DIR

owner=$1
repo=$2
target_sha=$3

# Ensure that all variables required to run are given, otherwise throw
# an error.
for VARNAME in owner repo target_sha; do
[[ -z "${!VARNAME:-}" ]] && echo "ERROR: $VARNAME not set" && exit 1;
done

# Bootstrap the app.
source utils.sh
bootstrap drivers/release-bot

# Run the app.

# First find the target branch.
echo "Getting target branch..."
target_branch=$(node get_backport_target.mjs -o $owner -n $repo -h $target_sha)
if [ -z "${target_branch}" ]; then
    echo "No matching cherry-pick comment!"
    popd
    exit 0
fi
echo "Target branch: $target_branch"
echo "Getting target branch... done."

# Get a github access token for the git checkout.
echo "Getting github token..."
token=$(bash ./get-access-token.sh $repo $owner)
if [ -z "${token}" ]; then
    echo "Failed to get github access token!"
    popd
    exit 1
fi
echo "Getting github token... done."

# Make the git checkout and create a new branch.
echo "Creating the git checkout..."
dirname=$(mktemp -d)
branch="cherry-pick-$target_branch-$target_sha"
git clone https://github.com/$owner/$repo.git $dirname

pushd $dirname
git config user.email "167856002+mongodb-dbx-release-bot[bot]@users.noreply.github.com"
git config user.name "mongodb-dbx-release-bot[bot]"
git remote set-url origin https://x-access-token:${token}@github.com/$owner/$repo.git
git checkout -b $branch "origin/$target_branch"
echo "Creating the git checkout... done."

# Attempt to make the cherry-pick.
echo "Creating the cherry-pick..."
old_title=$(git --no-pager log $target_sha --pretty=%B | head -n 1)
title="${old_title} [${target_branch}]"
body="Cherry-pick of $target_sha to $target_branch"
status=0
git cherry-pick -x -m1 $target_sha > /dev/null 2>&1 || {
    status=$?
}
if [ $status == 0 ]; then
    # If the cherry-pick succeeds, push the branch and make a PR.
    echo "Creating the cherry-pick..."
    echo "Creating the PR..."
    git push origin $branch
    resp=$(curl -L \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "{\"title\":\"${title}\",\"body\":\"${body}\",\"head\":\"${branch}\",\"base\":\"${target_branch}\"}" \
        --url https://api.github.com/repos/$owner/$repo/pulls)
    echo $resp | jq '.html_url'
    echo "Creating the PR... done."
    popd
else
    # If the cherry-pick fails, make a comment.
    echo "Creating the cherry-pick... failed!"
    echo "Creating the PR comment..."
    popd
    message="Sorry, unable to cherry-pick to $target_branch"
    cat << EOF > comment.txt
$message, please backport manually. Here are approximate instructions:

1. Checkout backport branch and update it.

\`\`\`
git checkout -b ${branch} ${target_branch}

git fetch origin ${target_sha}
\`\`\`

2. Cherry pick the first parent branch of the this PR on top of the older branch:
\`\`\`
git cherry-pick -x -m1 ${target_sha}
\`\`\`

3. You will likely have some merge/cherry-pick conflicts here, fix them and commit:

\`\`\`
git commit -am {message}
\`\`\`

4. Push to a named branch:

\`\`\`
git push origin ${branch}
\`\`\`

5. Create a PR against branch ${target_branch}. I would have named this PR:

> "$title"
EOF
    node create_or_modify_comment.mjs -o $owner -n $repo -m $message -c comment.txt -h $target_sha -s "closed"
    rm comment.txt
    echo "Creating the PR comment... done."
fi

rm -rf $dirname
popd
