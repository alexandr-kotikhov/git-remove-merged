#
# Author: Alexandr Kotikhov
#

set -e

declare DRY_RUN='YES'
declare -a BASE=() # default - current branch
declare -a INCLUDE=()
declare -a EXCLUDE=()
declare -a MASTER=() # default 'master'
declare SINCE='7 days ago'
declare LOCAL_ONLY='NO'
declare CURRENT_BRANCH

function showHelp() {
  cat <<EOF

Deletes merged branches.

USAGE:
git-remove-merged.sh [-r] [-b reg-exp]* [-i reg-exp]* [-e reg-exp]* [-s 'duration expression'] [-m name]* [-l]

Options:
  r   remove command, without this option it runs in 'Dry run' mode just showing what it is going to do.
  b   define expression selecting base branch, by default it is current branch, example: -b '/release/.*'
  i   include only matched branches, example: -i 'hotfix/.*'
  e   exclude matched branches from removing, example: -e 'release/.*' -e 'develop'
  s   remove only branches that are older than 'duration expression', by default '7 days ago'
  l   remove only local branches
  m   define master branch name (that will be excluded), default is 'master', example: -m main

  where:
    [...] = optional;
    * = the option can be set multiple times;
    reg-exp = any Bash regular expression that process branch ref in format "refs/heads/branch-name" or
                "refs/remotes/origin/branch-name". Do not use spaces in the regular expression.

EXAMPLES:
  # removes merged into local 'master' branch and contains 'XC-' in name.
  git-remove-merged.sh -l -r -b refs/heads/master -i '/XC-' | tee git-remove-merged.log

  # removes merged into any remote 'release' branches or into 'master' branch.
  git-remove-merged.sh -r -b '/master\$' -b '/remotes/.*/release/' -s '1 day ago'

  # removes merged into any 'release' branches, excluding 'main' and 'master' branches.
  git-remove-merged.sh -r -b '/release/' -m main -m master

EOF
}


matchAnyRegExp() {
  local -n arr=$2
  local regExp
  for regExp in "${arr[@]}"; do
    if [[ "$1" =~ $regExp ]]; then
      return 0
    fi
  done
  return 2
}

matchAny() {
  local -n arr=$2
  for val in "${arr[@]}"; do
    if [[ "$1" == "$val" ]]; then
      return 0
    fi
  done
  return 2
}

dumpMap() {
  local -n map=$1
  for key in "${!map[@]}"; do
    echo "  $key => ${map[$key]}"
  done
}


echo 'Processing parameters...'

while getopts 'i:e:b:m:s:rhl' opt; do
  case ${opt} in
  r) DRY_RUN='NO' ;;
  b) BASE+=("$OPTARG") ;;
  i) INCLUDE+=("$OPTARG") ;;
  e) EXCLUDE+=("$OPTARG") ;;
  s) SINCE="$OPTARG" ;;
  m) MASTER+=("$OPTARG") ;;
  l) LOCAL_ONLY='YES' ;;
  h)
    showHelp >&2
    exit 0
    ;;
  \?)
    showHelp >&2
    exit 1
    ;;
  esac
done

CURRENT_BRANCH="$(git symbolic-ref -q HEAD)"
mapfile -t branches < <(git branch -a --format='%(refname)')
echo "There are ${#branches[@]} branches."

if [ ${#MASTER[@]} -eq 0 ]; then
  MASTER=('master')
fi

if [ ${#BASE[@]} -eq 0 ]; then
  BASE=("$CURRENT_BRANCH")
fi

echo 'Analyzing branches...'

git fetch

echo "Getting branches merged to branch(s) ${BASE[*]}..."
declare -A toDelete # map merged-branch-ref to base-branch-ref
declare -A toSkip
for br in "${branches[@]}"; do
  if matchAnyRegExp "$br" BASE; then
    mapfile -t merged < <(git branch -a --merged "$br" --format='%(refname)')
    echo "  there are ${#merged[@]} merged branches into '$br' base branch"
    for branchRef in "${merged[@]}"; do

      if [ -v "toDelete[$branchRef]" ]; then
        continue # already in toDelete
      fi
      if [ -v "toSkip[$branchRef]" ]; then
        continue # already in toSkip
      fi

      if [[ $branchRef =~ refs/remotes/.* ]]; then
        IFS='/' read -r refs type origin branch <<<"$branchRef"
        if [[ "$LOCAL_ONLY" == 'YES' ]]; then
           toSkip[$branchRef]='it is not local branch'
           continue # skip remote branch
        fi
      else
        origin=''
        IFS='/' read -r refs type branch <<<"$branchRef"
      fi

      if matchAnyRegExp "$branchRef" BASE; then
        toSkip[$branchRef]='it is a base branch'
        continue
      fi

      if matchAny "$branch" MASTER; then
        toSkip[$branchRef]='it is a master branch'
        continue
      fi

      if [ ${#INCLUDE[@]} -gt 0 ]; then
        if ! matchAnyRegExp "$branchRef" INCLUDE; then
          toSkip[$branchRef]='not match'
          continue
        fi
      fi

      if matchAnyRegExp "$branchRef" EXCLUDE; then
        toSkip[$branchRef]='excluded'
        continue
      fi

      if [[ "$branch" == 'HEAD' ]]; then
        toSkip[$branchRef]='it is the current branch'
        continue
      fi

      toDelete[$branchRef]="$br"
    done
  fi
done

echo 'Skipped branches:'
declare -a SKIPPED
SKIPPED=("${!toSkip[@]}")
dumpMap toSkip


echo 'Merged branches to delete:'
declare -a BRANCHES
BRANCHES=("${!toDelete[@]}")
dumpMap toDelete

echo "Total: ${#BRANCHES[@]} to delete, ${#SKIPPED[@]} will be skipped."

echo "Deleting branches that have already been merged into the branch(es): [${BASE[*]}] earlier than ${SINCE},"
if [[ "$LOCAL_ONLY" == 'YES' ]]; then
  echo '  removing only local branches,'
fi
if [ ${#INCLUDE[@]} -gt 0 ]; then
  echo "  including branches by mask(s): [${INCLUDE[*]}],"
fi
if [ ${#EXCLUDE[@]} -gt 0 ]; then
  echo "  excluding branches by mask(s): [${EXCLUDE[*]}],"
fi
if [[ "$DRY_RUN" == 'YES' ]]; then
  echo "  dry run is active, to remove merged branches set '-r' option."
fi

echo 'Press ENTER to continue or CTRL-C to terminate...'
read -r


echo ''
if [[ "$DRY_RUN" == 'NO' ]]; then
  echo 'Removing merged branches:'
else
  echo 'Dry run:'
fi

declare refName
declare refs
declare type
declare origin
declare branch
declare -a TOO_YOUNG=()


for refName in "${BRANCHES[@]}"; do

  echo ''
  if [[ $refName =~ refs/remotes/.* ]]; then
    IFS='/' read -r refs type origin branch <<<"$refName"
    echo "REMOTE> $refs/$type/$origin/$branch"
  else
    origin=''
    IFS='/' read -r refs type branch <<<"$refName"
    echo "LOCAL> $refs/$type/$branch"
  fi

  commit_hash=$(git merge-base "$refName" "${toDelete[$refName]}")
  common_commit=$(git log -1 "$commit_hash" --since="$SINCE")

  echo "The last commit in the branch:"
  git log -1 "${commit_hash}" | head -n 10
  commit_description=$(git log -1 "${commit_hash}" --format='%aI, %aN, %s')

  if [[ ! "$common_commit" == '' ]]; then
    TOO_YOUNG+=("$branch - isn't old: $commit_description")
    echo '  skipped, this branch isn`t that old.'
  else

    echo "Removing the branch '$refName'..."
    if [[ "$DRY_RUN" == 'NO' ]]; then
      if [[ "$origin" == '' ]]; then
        git branch -D "$branch"
        echo 'The local branch is successfully removed.'
      else
        git push "$origin" --delete "$branch" --no-verify
        echo 'The branch is successfully removed from the server.'
      fi
    else
      if [[ "$origin" == '' ]]; then
        echo "> git branch -D $branch"
      else
        echo "> git push $origin --delete $branch --no-verify"
      fi
    fi

  fi

done


if [ ${#TOO_YOUNG[@]} -gt 0 ]; then
  echo ''
  echo "${#TOO_YOUNG[@]} branches were skipped because they are too young:"
  for branch in "${TOO_YOUNG[@]}"; do
    echo "  ${branch}"
  done
fi
