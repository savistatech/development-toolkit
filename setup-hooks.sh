#!/bin/bash

TARGET_DIR="${1:-.}"
cd "$TARGET_DIR" || { echo "Target directory not found."; exit 1; }

# --- Detect package manager from lockfile ---
# Checks local dir first (handles hybrid monorepos where each package has its own PM)
# Falls back to root if no lockfile found locally
detect_pm() {
  local check_dir="$1"
  local fallback_dir="$2"

  for dir in "$check_dir" "$fallback_dir"; do
    [ -z "$dir" ] && continue
    if [ -f "$dir/bun.lockb" ] || [ -f "$dir/bun.lock" ]; then
      echo "bun"; return
    elif [ -f "$dir/pnpm-lock.yaml" ]; then
      echo "pnpm"; return
    elif [ -f "$dir/yarn.lock" ]; then
      echo "yarn"; return
    elif [ -f "$dir/package-lock.json" ]; then
      echo "npm"; return
    fi
  done

  echo "npm" # hard fallback
}

# --- Core setup logic, runs per package ---
setup_husky() {
  local PKG_DIR="$1"
  local ROOT_DIR="$2"

  echo ""
  echo "▶ Setting up hooks in: $PKG_DIR"

  cd "$PKG_DIR" || { echo "[WARN] Could not cd into $PKG_DIR, skipping."; return; }

  # Local lockfile takes priority; root lockfile is fallback
  local PM
  PM=$(detect_pm "$PKG_DIR" "$ROOT_DIR")
  echo "[INFO] Package manager: $PM"

  local INSTALL_CMD RUN_CMD
  case "$PM" in
    bun)  INSTALL_CMD="bun add --dev husky" ;;
    pnpm) INSTALL_CMD="pnpm add --save-dev husky" ;;
    yarn) INSTALL_CMD="yarn add --dev husky" ;;
    *)    INSTALL_CMD="npm install --save-dev husky" ;;
  esac
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

  # --- Add prepare script only if not already present ---
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
    echo "[INFO] 'prepare' script already exists. Skipping."
  fi

  mkdir -p .husky

  # --- Pre-commit: skip if already exists ---
  if [ -s ".husky/pre-commit" ]; then
    echo "[INFO] Existing pre-commit hook found. Leaving it untouched."
  else
    if node -e "const pkg=require('./package.json'); process.exit(pkg.scripts && pkg.scripts.test ? 0 : 1);" 2>/dev/null; then
      echo "Detected 'test' script. Injecting pre-commit hook..."
      printf '#!/bin/sh\n%s test\n' "$RUN_CMD" > .husky/pre-commit
      chmod +x .husky/pre-commit
    else
      echo "[INFO] No 'test' script found. Skipping pre-commit hook."
    fi
  fi

  # --- Pre-push: branch protection ---
  echo "Injecting branch protection pre-push hook..."
  cat << 'EOF' > .husky/pre-push
#!/bin/sh
PROTECTED_BRANCHES="main dev test"

block_push() {
  echo "==========================================================" >&2
  echo "[CRITICAL ERROR] Direct pushes to [main, dev, test] are forbidden." >&2
  echo "Move your changes to a feature branch and submit a Pull Request." >&2
  echo "==========================================================" >&2
  exit 1
}

# Method 1: stdin (CLI git push)
while read local_ref local_sha remote_ref remote_sha
do
  branch=$(echo "$remote_ref" | sed 's|refs/heads/||')
  for protected in $PROTECTED_BRANCHES; do
    if [ "$branch" = "$protected" ]; then
      block_push
    fi
  done
done

# Method 2: current branch fallback (GUI clients skip stdin)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
for protected in $PROTECTED_BRANCHES; do
  if [ "$CURRENT_BRANCH" = "$protected" ]; then
    block_push
  fi
done

exit 0
EOF
  chmod +x .husky/pre-push

  echo "[SUCCESS] Hooks configured in $PKG_DIR"
  cd "$ROOT_DIR"
}

# -------------------------------------------------------
# Entry point
# -------------------------------------------------------
ROOT_DIR=$(pwd)

if [ ! -f "package.json" ] && [ -z "$(find . -maxdepth 2 -name 'package.json' 2>/dev/null)" ]; then
  echo "[ERROR] No package.json found in $(pwd) or any subdirectory."
  exit 1
fi

# Collect targets: root + 1 level deep, skip node_modules
TARGETS=()
[ -f "package.json" ] && TARGETS+=("$ROOT_DIR")
while IFS= read -r pkg; do
  dir=$(dirname "$pkg")
  case "$dir" in
    *node_modules*) continue ;;
  esac
  [ "$dir" != "$ROOT_DIR" ] && TARGETS+=("$dir")
done < <(find . -maxdepth 2 -name "package.json" ! -path "*/node_modules/*" 2>/dev/null)

TARGETS=($(printf '%s\n' "${TARGETS[@]}" | sort -u))

echo "Found ${#TARGETS[@]} package(s) to configure:"
for t in "${TARGETS[@]}"; do
  # Show which PM each target will use for clarity
  pm=$(detect_pm "$t" "$ROOT_DIR")
  echo "  - $t  ($pm)"
done

for target in "${TARGETS[@]}"; do
  setup_husky "$target" "$ROOT_DIR"
done

echo ""
echo "=========================================================="
echo "[DONE] All packages configured."
echo "=========================================================="
