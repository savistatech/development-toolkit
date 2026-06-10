#!/bin/bash
TARGET_DIR="${1:-.}"
cd "$TARGET_DIR" || { echo "Target directory not found."; exit 1; }

if [ ! -f "package.json" ]; then
  echo "[ERROR] package.json not found in $(pwd)."
  echo "Ensure you are running this script inside a valid React / Node.js project root."
  exit 1
fi

# Backup existing pre-commit hook to a temp file BEFORE husky init tramples it
TMPFILE=$(mktemp)
PRE_COMMIT_EXISTS=false
if [ -s ".husky/pre-commit" ]; then
  cp .husky/pre-commit "$TMPFILE"
  PRE_COMMIT_EXISTS=true
  echo "[INFO] Existing pre-commit hook backed up to $TMPFILE"
fi

echo "Installing Husky and generating configurations..."
npx husky init
mkdir -p .husky

# --- Restore or inject pre-commit hook ---
if [ "$PRE_COMMIT_EXISTS" = true ]; then
  echo "[INFO] Restoring original pre-commit hook..."
  cp "$TMPFILE" .husky/pre-commit
  chmod +x .husky/pre-commit
else
  if node -e "const pkg = require('./package.json'); process.exit(pkg.scripts && pkg.scripts.test ? 0 : 1);" 2>/dev/null; then
    echo "Detected 'test' script in package.json. Injecting pre-commit hook..."
    cat << 'EOF' > .husky/pre-commit
#!/bin/sh
npm test
EOF
    chmod +x .husky/pre-commit
  else
    echo "[INFO] No 'test' script found in package.json. Skipping pre-commit hook creation."
  fi
fi

# Cleanup temp file
rm -f "$TMPFILE"
# -----------------------------------------

echo "Injecting local branch protection constraints..."
cat << 'EOF' > .husky/pre-push
#!/bin/sh

PROTECTED_BRANCHES="main dev test"

# --- Method 1: stdin-based check (works for CLI git push) ---
while read local_ref local_sha remote_ref remote_sha
do
  branch=$(echo "$remote_ref" | sed 's|refs/heads/||')
  for protected in $PROTECTED_BRANCHES; do
    if [ "$branch" = "$protected" ]; then
      echo "=========================================================="
      echo "[CRITICAL ERROR] Direct pushes to [main, dev, test] are forbidden."
      echo "Move your changes to a feature branch and submit a Pull Request."
      echo "=========================================================="
      exit 1
    fi
  done
done

# --- Method 2: current branch check (fallback for GUI clients) ---
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
for protected in $PROTECTED_BRANCHES; do
  if [ "$CURRENT_BRANCH" = "$protected" ]; then
    echo "=========================================================="
    echo "[CRITICAL ERROR] Direct pushes to [main, dev, test] are forbidden."
    echo "Move your changes to a feature branch and submit a Pull Request."
    echo "=========================================================="
    exit 1
  fi
done

exit 0
EOF

chmod +x .husky/pre-push

echo "=========================================================="
echo "[SUCCESS] Configuration complete."
echo "Pre-push validation enforced on main, dev, and test."
echo "Remember to run 'npm install' or 'yarn install' if you haven't already."
echo "=========================================================="
