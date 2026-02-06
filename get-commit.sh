#!/bin/bash

#############################################
# CONFIGURATION
#############################################

GITLAB_EMAIL="quentin.gosset@infrabel.be"

GITHUB_EMAIL="quentingosset7500@hotmail.com"
GITHUB_NAME="Quentin Gosset"

GITHUB_REMOTE="https://github.com/quentingosset/infrabel-contributions.git"
OUTPUT_DIR="shadow-repo"

#############################################

echo "========================================="
echo "   GITLAB → GITHUB CONTRIBUTION TRACKER"
echo "========================================="
echo ""

PARENT_DIR="$(pwd)"
SCRIPT_NAME="$(basename "$0")"

#############################################
# Clone ou pull
#############################################

if [ ! -d "$OUTPUT_DIR/.git" ]; then
  echo "[+] Clone du repo GitHub..."
  git clone "$GITHUB_REMOTE" "$OUTPUT_DIR"
else
  echo "[+] Pull du repo existant..."
  git -C "$OUTPUT_DIR" pull --rebase || true
fi

#############################################
# Fichiers d'état (chemins absolus)
#############################################

HASH_FILE="$PARENT_DIR/$OUTPUT_DIR/replayed_hashes.txt"
COUNTS_FILE="$PARENT_DIR/$OUTPUT_DIR/project_counts.txt"

touch "$HASH_FILE"
touch "$COUNTS_FILE"

TOTAL_NEW=0

#############################################
# Scan projets
#############################################

for dir in */ ; do
  PROJECT_NAME="$(basename "$dir")"

  if [ "$PROJECT_NAME" = "$OUTPUT_DIR" ]; then
    continue
  fi

  if [ ! -d "$dir/.git" ]; then
    continue
  fi

  echo "[+] Scan $PROJECT_NAME"

  git -C "$dir" log --reverse --author="$GITLAB_EMAIL" --pretty=format:"%H" > commit_list.txt

  PROJECT_NEW=0

  while read -r COMMIT_HASH; do
    [ -z "$COMMIT_HASH" ] && continue

    if grep -Fxq "$COMMIT_HASH" "$HASH_FILE" 2>/dev/null; then
      continue
    fi

    COMMIT_DATE="$(git -C "$dir" show -s --format=%ai "$COMMIT_HASH")"
    MESSAGE="$(git -C "$dir" show -s --format=%s "$COMMIT_HASH")"

    export GIT_AUTHOR_NAME="$GITHUB_NAME"
    export GIT_AUTHOR_EMAIL="$GITHUB_EMAIL"
    export GIT_AUTHOR_DATE="$COMMIT_DATE"
    export GIT_COMMITTER_NAME="$GITHUB_NAME"
    export GIT_COMMITTER_EMAIL="$GITHUB_EMAIL"
    export GIT_COMMITTER_DATE="$COMMIT_DATE"

    git -C "$OUTPUT_DIR" commit --allow-empty -m "$MESSAGE" >/dev/null 2>&1

    echo "$COMMIT_HASH" >> "$HASH_FILE"

    PROJECT_NEW=$((PROJECT_NEW + 1))
    TOTAL_NEW=$((TOTAL_NEW + 1))

  done < commit_list.txt

  rm -f commit_list.txt

  if [ "$PROJECT_NEW" -gt 0 ]; then
    CURRENT="$(grep "^${PROJECT_NAME}=" "$COUNTS_FILE" 2>/dev/null | cut -d'=' -f2)"
    [ -z "$CURRENT" ] && CURRENT=0

    UPDATED=$((CURRENT + PROJECT_NEW))

    grep -v "^${PROJECT_NAME}=" "$COUNTS_FILE" > "${COUNTS_FILE}.tmp" 2>/dev/null || true
    echo "${PROJECT_NAME}=${UPDATED}" >> "${COUNTS_FILE}.tmp"
    mv "${COUNTS_FILE}.tmp" "$COUNTS_FILE"
  fi
done

#############################################
# Génération README
#############################################

cd "$OUTPUT_DIR" || exit 1

TODAY="$(date +"%d/%m/%Y")"
TOTAL_REPLAYED="$(wc -l < replayed_hashes.txt | tr -d ' ')"

{
  echo "# GitLab Contribution Archive"
  echo ""
  echo "Empty commits replayed from private GitLab projects."
  echo ""
  echo "## Contributions by project"
  echo ""

  sort -t'=' -k2,2nr project_counts.txt 2>/dev/null | while IFS= read -r line; do
    [ -z "$line" ] && continue
    proj="${line%%=*}"
    cnt="${line#*=}"
    if [ "$cnt" -gt 0 ] 2>/dev/null; then
      echo "- **$proj** → $cnt contributions"
    fi
  done

  echo ""
  echo "---"
  echo "**Author:** $GITHUB_NAME"
  echo ""
  echo "**Email used:** $GITHUB_EMAIL"
  echo ""
  echo "**Total commits replayed:** $TOTAL_REPLAYED"
  echo ""
  echo "**Last refresh:** $TODAY"
  echo ""
  echo "**New commits added this run:** $TOTAL_NEW"
  echo ""
  echo "_Automatically generated._"

} > README.md

#############################################
# Commit & push
#############################################

cp "$PARENT_DIR/$SCRIPT_NAME" "./$SCRIPT_NAME"
chmod +x "$SCRIPT_NAME"

git add README.md replayed_hashes.txt project_counts.txt "$SCRIPT_NAME"

if git diff --cached --quiet; then
  echo ""
  echo "[✔] Aucun changement détecté."
else
  git commit -m "Refresh contributions $TODAY"
  git push origin main
  echo ""
  echo "[✔] Push effectué."
fi

echo ""
echo "[✔] Script terminé."
echo "    Nouveaux commits rejoués : $TOTAL_NEW"
