#!/bin/bash
TARGET_DIR="${1:-.}"
cd "$TARGET_DIR" || { echo "Target directory not found."; exit 1; }

if [ ! -f "package.json" ]; then
  echo "[ERROR] package.json not found in $(pwd)."
  echo "Ensure you are running this script inside a valid React / Node.js project root."
  exit 1
fi

# --- Detect package manager from lockfile ---
detect_pm() {
  if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    echo "bun"
  elif [ -f "pnpm-lock.yaml" ]; then
    echo "pnpm"
  elif [ -f "yarn.lock" ]; then
    echo "yarn"
  else
    echo "npm"
  fi
}

PM=$(detect_pm)
echo "[INFO] Detected package manager: $PM"

# --- Install command per PM ---
case "$PM" in
  bun)  INSTALL_CMD="bun add --dev husky" ;;
  pnpm) INSTALL_CMD="pnpm add --save-dev husky" ;;
  yarn) INSTALL_CMD="yarn add --dev husky" ;;
  *)    INSTALL_CMD="npm install --save-dev husky" ;;
esac

# --- Run command per PM ---
case "$PM" in
  bun)  RUN_CMD="bun run" ;;
  pnpm) RUN_CMD="pnpm run" ;;
  yarn) RUN_CMD="yarn" ;;
  *)    RUN_CMD="npm run" ;;
esac

# --- Check if husky is already installed ---
if node -e "require('husky')" 2>/dev/null; then
  echo "[INFO] Husky already installed. Skipping installation."
else
  echo "Installing Husky via $PM..."
  $INSTALL_CMD
fi

# --- Add prepare script to package.json only if not already present ---
if ! node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.prepare ? 0 : 1);" 2>/dev/null; then
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    pkg.scripts = pkg.scripts || {};
    pkg.scripts.prepare = 'husky';
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
  "
  echo "[INFO] Added 'prepare': 'husky' to package.json"
else
  echo "[INFO] 'prepare' script already exists in package.json. Skipping."
fi

mkdir -p .husky

# --- Pre-commit: only inject if file does not already exist ---
if [ -s ".husky/pre-commit" ]; then
  echo "[INFO] Existing pre-commit hook found. Leaving it untouched."
else
  if node -e "const pkg=require('./package.json'); process.exit(pkg.scripts && pkg.scripts.test ? 0 : 1);" 2>/dev/null; then
    echo "Detected 'test' script. Injecting pre-commit hook..."
    cat << 'EOF' > .husky/pre-commit
#!/bin/sh
npm test
EOF
    # Rewrite with correct PM
    echo "#!/bin/sh" > .husky/pre-commit
    echo "$RUN_CMD test" >> .husky/pre-commit
    chmod +x .husky/pre-commit
  else
    echo "[INFO] No 'test' script found. Skipping pre-commit hook creation."
  fi
fi

# --- Pre-push: branch protection (this script always owns this file) ---
echo "Injecting branch protection pre-push hook..."
cat << 'EOF' > .husky/pre-push
#!/bin/sh

PROTECTED_BRANCHES="main dev test"

# Method 1: stdin (CLI git push)
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

# Method 2: current branch fallback (GUI clients skip stdin)
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
echo "Package manager: $PM"
echo "Pre-push validation enforced on main, dev, and test."
echo "=========================================================="
