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

function showHelp() {
    echo ""
    echo "Удаление смерженных веток"
    echo ""
    echo "Использование:"
    echo "git-remove-merged.sh [-r] [-b base-branch] [-i bash-reg-exp] [-e bash-reg-exp] [-s 'duration expression']"
    echo ""
    echo "пример: git-remove-merged.sh -r -b master -i 'XC-.*' | tee git-remove-merged.log"
}

while getopts "i:e:b:d:s:rh" opt; do
  case ${opt} in
    r ) DRY_RUN='NO';;

    b ) BASE="$OPTARG";;

    i ) INCLUDE="$OPTARG";;

    e ) EXCLUDE="$OPTARG";;

    s ) SINCE="$OPTARG";;

    \? )
      echo "Недопустимая опция: -${opt}." 1>&2
      showHelp >&2
      exit 1
      ;;
    : )
      echo "Не задан аргумент у опции -${opt}." 1>&2
      showHelp >&2
      exit 1
      ;;
  esac
done

echo "Удаление веток, которые уже вмержены базовую ветку '${BASE}' более ${SINCE},"
echo "  включая ветки по маске = '$INCLUDE',"
echo "  исключая ветки по маске '$EXCLUDE',"
if [[ "$DRY_RUN" == "YES" ]]; then
    echo "  xолостой прогон активирован, для включения в режиме обновления укажите параметр '-r'."
fi

echo "Синхронизация с сервером..."
git pull

echo "Получение списка смерженных веток..."
BRANCHES=( $(git branch -a --merged "$BASE" --format='%(refname)') )

echo "Все смерженные ветки, ${#BRANCHES[@]}:"
echo "${BRANCHES[@]}"

echo "Обработка..."

NOT_DELETED=()
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
    NOT_DELETED+=("$branch - базовая")
    echo "  пропускаем, так-как это базовая ветка."
    continue
  elif [[ "$branch" == "master" ]]; then
    NOT_DELETED+=("$branch - master")
    echo "  пропускаем, так-как это master ветка."
    continue
  elif [[ ! "$INCLUDE" == "" && ! "$branch" =~ $INCLUDE ]]; then
    NOT_DELETED+=("$branch - не подходит")
    echo "  пропускаем, так-как не попадает под условие $INCLUDE."
    continue
  elif [[ ! "$EXCLUDE" == "" && "$branch" =~ $EXCLUDE ]]; then
    NOT_DELETED+=("$branch - исключена")
    echo "  пропускаем, так-как попадает под исключение $EXCLUDE."
    continue
  elif [[ "$branch" == "HEAD" ]]; then
    NOT_DELETED+=("$branch - текущая")
    echo "  пропускаем, так-как это текущая ветка."
    continue
  fi

  commit_hash=$(git merge-base "$refname" "$BASE")
  common_commit=$(git log -1 "$commit_hash" --since="$SINCE")

  echo "Последний коммит в ветке:"
  git log -1 ${commit_hash} | head -n 10
  commit_description=$(git log -1 ${commit_hash} --format='%aI, %aN, %s')

  if [[ ! "$common_commit" == "" ]]; then
    NOT_DELETED+=("$branch - не старая: $commit_description")
    echo "Пропускаем, так-как эта ветка не достаточно старая."
  else

    if [[ "$DRY_RUN" == 'NO' ]]; then
      if [[ "$origin" == "" ]]; then
        echo "Удаление ветки $refname> git branch -d $branch --no-verify"
        git branch -d "$branch" --no-verify
        echo "Успешно удалена локальная ветка."
      else
        echo "Удаление ветки $refname> git push $origin --delete $branch --no-verify"
        git push "$origin" --delete "$branch" --no-verify
        echo "Успешно удалена ветка с сервера."
      fi
    else
      echo "Эмуляция удаления ветки $refname:"
      if [[ "$origin" == "" ]]; then
        echo "git branch -d $branch --no-verify"
      else
        echo "git push $origin --delete $branch --no-verify"
      fi
    fi

  fi

done


echo "Смерженные в ${BASE} ветки, но оставшиеся не удаленными:"
for branch in "${NOT_DELETED[@]}"; do
  echo "  ${branch}"
done
