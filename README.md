# thanks-github
Script to split a GitHub Pull Request Review into _n_ smaller reviews to avoid the GitHub unicorn page that occurs after doing large reviews.

```
Usage: ././split-review.sh
  -o | --organisation <org name>
  -r | --repo <repo name>
  -p | --pr-number <number> # PR you want to operate on
  -i | --review-id <number> # The review you want to split into smaller pieces
  -s | --split <number>     # Number of reviews to create
```

Will create `--split-number` PR reviews in GitHub, each with a PENDING status. Since GitHub doesn't allow multiple reviews with a status of PENDING, you'll need to interactively eyeball and complete each PR review before the script can create the next one. In this sense the script is interactive - it does stuff, you check it out and accept/complete the review and then it continues.

## Requirements
- You'll need a personal access token with repo access in order to access the GitHub v3 API endpoints.
- Jq on the path
- Bash (tested on MacOS with ancient Bash 3.2.57)
- Curl

This is unsupported, will set your hair on fire, etc.
