# Repository Initialization Toolkit

Internal utility engine designed to standardize local development environments, automate Git hook initialization, and prevent accidental direct pushes to protected branches (`main`, `dev`, `test`).

## Core Functionality

This repository distributes the automated initialization script `setup-hooks.sh`. When executed within a Node.js/React ecosystem root directory, it configures Husky (v9) and binds a local validation interceptor to the `pre-push` Git lifecycle sequence.

If a developer attempts to push code directly to `main`, `dev`, or `test`, the hook terminates the process on their local machine before any data reaches GitHub.

## Prerequisites

* Unix-based terminal environment (Linux, macOS, WSL)
* Project must be initialized with a root `package.json` file
* Git initialized locally (`git init`)

## Installation & Usage

Execute this script **immediately** after creating a fresh project or cloning a repository that lacks branch constraints.

### Method A: Local Execution (Recommended)
Keep this repository cloned locally on your workstation to run its components across internal projects.

1. Navigate to the root directory of your target project.
2. Execute the script by pointing to its location on your disk:
```bash
   bash /path/to/development-toolkit/setup-hooks.sh
```

### Method B: Remote Network Execution
Run the script directly via network stream without needing a local clone of this toolkit repository:

```bash
curl -fsSL https://raw.githubusercontent.com/savistatech/development-toolkit/refs/heads/main/setup-hooks.sh | bash
```

## Post-Setup Verification

1. Confirm that a .husky/ directory has been generated in your project root.
2. Open your project's package.json and ensure the following initialization sequence was appended:
  ```json
  "scripts": {
     "prepare": "husky"
   }
   ```
3. Stage and commit the generated hook configuration files so they distribute to the rest of the team:
  ```bash
  git add .husky/pre-push package.json
  git commit -m "chore: enforce local branch protection policies"
  ```

## Critical Caveats & Bypass Risk

Team Enforcement: The rules are only deployed to other team members once they pull down the commit containing the modified .husky/ tree and execute npm install (which fires the prepare command).

Verify Bypass: Client-side hooks protect against developer negligence; they do not replace server-side security. Any developer can explicitly bypass this local script by running:
```bash
git push origin main --no-verify
```
