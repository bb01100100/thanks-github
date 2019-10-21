#!/bin/bash

PARAMS=""

while (( "$#" )); do
  case "$1" in
    -o|--org)
      ORGANISATION=$2
      shift 2
      ;;
    -r|--repo)
      REPO=$2
      shift 2
      ;;
    -p|--pr-number)
      PR_NUMBER=$2
      shift 2
      ;;
    -i|--review-id)
      ORIGINAL_REVIEW_ID=$2
      shift 2
      ;;
    -s|--split)
      REVIEW_SPLIT=$2
      shift 2
      ;;
    -h|--help)
		echo "" 
      echo "Github PR review splitter v0.1."
      echo "Takes a given PR review and (interactively) replaces with several smaller reviews."
      echo "This exists because GitHub times out on large (pfff) reviews with lots of suggestions"
      echo ""
      echo "Usage: $0"
      echo "  -o | --organisation <org name>"
      echo "  -r | --repo <repo name>"
      echo "  -p | --pr-number <number> # PR you want to operate on"
 		echo "  -i | --review-id <number> # The review you want to split into smaller pieces"
      echo "  -s | --split <number>     # Number of reviews to create "
		echo "" 
      exit 1
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

eval set -- "$PARAMS"

if [ -z "$ORGANISATION" ] || [ -z "$REPO" ] || [ -z "$PR_NUMBER" ] || [ -z "$ORIGINAL_REVIEW_ID" ]; then
 sh ./$0 -h
 exit 1
fi  

echo ""
echo "================================================================================"
echo "Carrying out an interactive PR review split, with the following parameters:"
echo "  Organisation $ORGANISATION, "
echo "  Repository   $REPO, "
echo "  PR number    $PR_NUMBER"
echo "  Original review ID to split $ORIGINAL_REVIEW_ID"
echo ""
echo "Splitting into $REVIEW_SPLIT smaller reviews."
echo "================================================================================"
echo ""
  


TOKEN=$(jq -r .token ~/.github-auth 4>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "  This script uses a github personal access token for GitHub API access. "
  echo "  It expects the token to live in ~/.githyb-auth but it could not find what it needed."
  echo '  File format is simple: {"username": "blah", "token": "moreblah"}'
  exit 1
fi


BASE_REVIEW_URL="https://api.github.com/repos/${ORGANISATION}/${REPO}/pulls/${PR_NUMBER}"


# The ID of the review we want to split into smaller reviews
#ORIGINAL_REVIEW_ID=303030020


# Header crap
AUTH_HEADER="Authorization: token ${TOKEN}"

# New trick; completion generator (compgen) builtin.. nice.
#if compgen -G "[1-9].json" > /dev/null; then
if [ $(ls [1-9].json 2>/dev/null| wc -l) -gt 0 ]; then
  echo ""
  echo "Looks like comments from $BASE_REVIEW_URL/comments has already been downloaded."
  echo "  If you don't want to use this data, then move/delete files matching glob [1-9].json"
  echo ""
  echo "  Hit enter to continue, or Control-C to cancel..."
  read waiter
else
	URL="${BASE_REVIEW_URL}/reviews/$ORIGINAL_REVIEW_ID/comments"
	# Build up the file list.
	for ((i=1; ; i+=1)); do
		contents=$(curl -H "${AUTH_HEADER}" -Ss "${URL}?page=$i")
		echo "On page $i of review ${ORIGINAL_REVIEW_ID}'s comments.." 1>&2
		echo "$contents" > $i.json
		if jq -e ' length == 0' >/dev/null; then 
			rm -f $i.json
			break
		fi <<< "$contents"
	done
   echo "Review data downloaded from GitHub"
fi

echo "Continuing..."


echo "Extracting comments out of data files..."
# Extract all comments using jq
jq -c '.[]|{"path": .path, "position": .position, "body": .body, "commit_id": .commit_id}' [1-9].json | jq -s '.'> all_comments.json
ORIGINAL_COMMENT_COUNT=$(jq -s '.[]|length' all_comments.json)


# Make sure that comments relate to a single commit; the script isn't clever enough to create smaller reviews on a per-commit basis

if [ $(jq '[.[]|.commit_id]|unique|length' all_comments.json) -gt 1 ]; then
  echo "The comments relate to more than on commit in the repo; "
  echo "this is beyond the scope of the script. Can't help you. So sorry."
  exit 1
fi


echo ""
echo "Ok, all of the review data has been downloaded into files matching the glob [1-9].json"
echo "And the comments have been extracted into 'all_comments.json'"
echo ""
echo ""
echo "*  Before we can split up review ${ORIGINAL_REVIEW_ID} into $REVIEW_SPLIT smaller reviews, "
echo "*  you will need to cancel the existing review (via the GitHub website, or via API call, etc)."
echo "*  This is because GitHub only allows one PENDING PR review at a time for a given user."
echo ""
echo "  Press (capital) P to proceed when the existing review has been cancelled:"
read -s -n 1 waiter

if [ "$waiter" == "P" ]; then
  echo ""
  echo "  Proceeding to create new PR reviews..."
else
  echo "  Ok, not proceeding. See you next time."
  exit 1
fi

# Split comments into two, ensuring we capture all comments inclusively.
COMMENTS_PER_REVIEW=$(( $(jq -s '.[]|length' all_comments.json ) / $REVIEW_SPLIT + 1 ))

echo ""
echo "Original review had $ORIGINAL_COMMENT_COUNT comments in it."
echo "Will create ${REVIEW_SPLIT} pull request reviews of (at most) $COMMENTS_PER_REVIEW comments each."

for end_idx in $(seq $COMMENTS_PER_REVIEW $COMMENTS_PER_REVIEW $(( $COMMENTS_PER_REVIEW * $REVIEW_SPLIT ))); do

   start_idx=$(( $end_idx - $COMMENTS_PER_REVIEW ))
   
   echo " Comment range indices are $start_idx -> $end_idx..."

   # Because we only work with a single commit, we can extract the commit id from any comment.
	REVIEW_COMMIT_ID=$(jq -r '.[0]|.commit_id' all_comments.json)
	echo " Review commit id is ${REVIEW_COMMIT_ID}"

   COMMENT_BATCH=$(jq --arg start_idx $start_idx --arg end_idx $end_idx '.[$start_idx|tonumber:$end_idx|tonumber]|del(.[].commit_id)' all_comments.json)

	DATA="{\"commit_id\":\"$REVIEW_COMMIT_ID\",\"comments\":${COMMENT_BATCH}}"
	SUBSET_FILENAME="${start_idx}--${end_idx}--review.json"
   echo " Saving subsets of comments to ${SUBSET_FILENAME}"
	echo "${DATA}" > "${SUBSET_FILENAME}"

	URL="${BASE_REVIEW_URL}/reviews"

   echo ""
   echo " Press (capital) P to proceed with creating a new PR review of $COMMENTS_PER_REVIEW comments.."
   read -s -n 1 waiter
   if [ "$waiter" == "P" ]; then
		curl -Ss --include -H "${AUTH_HEADER}" -Ss -H "Content-Type: application/json" -d "${DATA}" -XPOST "${URL}"
      echo ""
		echo "  Ok, check github to see what's happening.. "
      echo "  You should have a new PENDING review."
      echo "  Submit / complete the review, and when you're ready come back here."
      echo ""
      echo "Press enter when you're ready..."
		read -s waiter
   else
      echo ""
      echo "  NOT creating a PENDING review - no action taken."
   fi
done

echo "We're done here."
