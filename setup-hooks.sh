#!/bin/bash

# Target the directory passed as an argument, default to the current directory
TARGET_DIR="${1:-.}"

cd "$TARGET_DIR" || { echo "Target directory not found."; exit 1; }

# Fail-safe check for Node.js environment
if [ ! -f "package.json" ]; then
  echo "[ERROR] package.json not found in $(pwd)."
  echo "Ensure you are running this script inside a valid React / Node.js project root."
  exit 1
fi

echo "Installing Husky and generating configurations..."
# Automatically patches package.json with the prepare script and installs dependencies
npx husky init

# Ensure the target directory exists for hooks
mkdir -p .husky

echo "Injecting local branch protection constraints..."
cat << 'EOF' > .husky/pre-push
#!/bin/sh

# Intercept the target remote tracking branches during execution
while read local_ref local_sha remote_ref remote_sha
do
  if [ "$remote_ref" = "refs/heads/main" ] || [ "$remote_ref" = "refs/heads/dev" ] || [ "$remote_ref" = "refs/heads/test" ]; then
    echo "=========================================================="
    echo "[CRITICAL ERROR] Direct pushes to [main, dev, test] are forbidden."
    echo "Move your changes to a feature branch and submit a Pull Request."
    echo "=========================================================="
    exit 1
  fi
done

exit 0
EOF

# Grant absolute execution permission across UNIX-based environments
chmod +x .husky/pre-push

echo "=========================================================="
echo "[SUCCESS] Pre-push validation enforced on main, dev, and test."
echo "Remember to run 'npm install' or 'yarn install' if you haven't already."
echo "=========================================================="
