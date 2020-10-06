#!/usr/bin/env bash
#
# Author: Alexandr Kotikhov
#

set -e

declare BASE='develop'
declare DRY_RUN='YES'
declare INCLUDE=''
declare EXCLUDE=''
declare SINCE='7 days ago'
declare MASTER='master' # skipped

function showHelp() {
    echo ""
    echo "Deletes merged branches."
    echo ""
    echo "USAGE:"
    echo "git-remove-merged.sh [-r] [-b base-branch] [-i bash-reg-exp] [-e bash-reg-exp] [-s 'duration expression'] [-m master-branch-name]"
    echo ""
    echo "Example: git-remove-merged.sh -r -b master -i 'XC-.*' | tee git-remove-merged.log"
}


function dump() {
  echo ""
  if [[ "$DRY_RUN" == 'NO' ]]; then
    echo "Removed branches:"
  else
    echo "Branches to remove:"
  fi
  for branch in "${DELETED[@]}"; do
    echo "  ${branch}"
  done
  echo "Total ${#DELETED[@]}."

  echo ""
  echo "Merged into '${BASE}' branches but still not deleted:"
  for branch in "${NOT_DELETED[@]}"; do
    echo "  ${branch}"
  done
  echo "Total ${#NOT_DELETED[@]}."
}


while getopts "i:e:b:d:m:s:rh" opt; do
  case ${opt} in
    r ) DRY_RUN='NO';;

    b ) BASE="$OPTARG";;

    i ) INCLUDE="$OPTARG";;

    e ) EXCLUDE="$OPTARG";;

    s ) SINCE="$OPTARG";;

    m ) MASTER="$OPTARG";;

    h ) 
      showHelp >&2
      exit 0
      ;;

    \? )
      showHelp >&2
      exit 1
      ;;
      
  esac
done

echo "Removes branches that were already merged into the branch '${BASE}' more than ${SINCE},"
echo "  including branches by mask '$INCLUDE',"
echo "  excluding branches by mask '$EXCLUDE',"
if [[ "$DRY_RUN" == "YES" ]]; then
    echo "  dry run is active, to remove merged branches set '-r' option."
fi

echo "Pull the server..."
git pull

echo "Getting merged branches..."
BRANCHES=( $(git branch -a --merged "$BASE" --format='%(refname)') )

echo "Merged branches:"
echo "${BRANCHES[@]}"

echo "Total ${#BRANCHES[@]} merged branches. Processing..."

set +e

NOT_DELETED=()
DELETED=()
for refname in "${BRANCHES[@]}"; do

  echo ""
  if [[ $refname == "refs/remotes/"* ]]; then
    IFS='/' read refs type origin branch<<<"$refname"
    echo "REMOTE> $refs/$type/$origin/$branch"
  else
    origin=''
    IFS='/' read refs type branch<<<"$refname"
    echo "LOCAL> $refs/$type/$branch"
  fi

  if [[ "$branch" == "$BASE" ]]; then
    NOT_DELETED+=("$branch - base")
    echo "  skipped, because it is the base branch."
    continue
  elif [[ "$branch" == "$MASTER" ]]; then
    NOT_DELETED+=("$branch - master")
    echo "  skipped, because it is the master branch."
    continue
  elif [[ ! "$INCLUDE" == "" && ! "$branch" =~ $INCLUDE ]]; then
    NOT_DELETED+=("$branch - not match")
    echo "  skipped, not match."
    continue
  elif [[ ! "$EXCLUDE" == "" && "$branch" =~ $EXCLUDE ]]; then
    NOT_DELETED+=("$branch - excluded")
    echo "  skipped, excluded."
    continue
  elif [[ "$branch" == "HEAD" ]]; then
    NOT_DELETED+=("$branch - current")
    echo "  skipped, because it is the current branch."
    continue
  fi

  commit_hash=$(git merge-base "$refname" "$BASE")
  common_commit=$(git log -1 "$commit_hash" --since="$SINCE")

  echo "The last commit in the branch:"
  git log -1 ${commit_hash} | head -n 10
  commit_description=$(git log -1 ${commit_hash} --format='%aI, %aN, %s')

  if [[ ! "$common_commit" == "" ]]; then
    NOT_DELETED+=("$branch - isn't old: $commit_description")
    echo "  skipped, this branch isn't that old."
  else

    echo "Removing the branch '$refname'..."
    if [[ "$DRY_RUN" == 'NO' ]]; then
      if [[ "$origin" == "" ]]; then
        git branch -d "$branch"
        if [ $? -eq 0 ]; then
          DELETED+=("$branch")
          echo "The local branch is successfuly removed."
        else  
          NOT_DELETED+=("$branch - ERROR: Cannot delete the local branch.")
          echo "Cannot delete the local branch."
        fi
      else
        git push "$origin" --delete "$branch" --no-verify
        if [ $? -eq 0 ]; then
          DELETED+=("$branch")
          echo "The branch is successfuly removed from the server."
        else  
          NOT_DELETED+=("$branch - ERROR: Cannot delete the branch from the server.")
          echo "Cannot delete the branch from the server."
        fi
      fi
    else
      if [[ "$origin" == "" ]]; then
        echo "> git branch -d $branch"
      else
        echo "> git push $origin --delete $branch --no-verify"
      fi
    fi

  fi

done

dump
