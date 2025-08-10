#!/bin/bash

# docker-install-sauces.sh: add sauces to path & ~/.bashrc

# this installer and the `secretsauce.sh` script require this to function correctly. others do not.
set -euo pipefail  # Exit on error, undefined var, pipe failure

# STILL needed: this is a fallback
# Function to find the Git root directory, ascending up to 6 levels
# Required for source line to be accurate and work from all locations
find_git_root() {
    local current_dir="$(pwd)"
    local max_levels=6
    local level=0
    local dir="$current_dir"

    while [[ $level -le $max_levels ]]; do
        if [[ -d "$dir/.git" ]]; then
            echo "$dir"
            return 0
        fi
        # Go up one level
        dir="$(dirname "$dir")"
        # If we've reached the root (e.g., /), stop early
        if [[ "$dir" == "/" ]] || [[ "$dir" == "//" ]]; then
            break
        fi
        ((level++))
    done

    echo "Error: .git directory not found within $max_levels parent directories." >&2
    return 1
}

find_project_root() {

  export PROJECT_ROOT=""
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Check if we are inside the 'docker' directory (current path contains /docker)
  if [[ "$PWD" == *"/docker" || "$PWD" == *"/docker/"* ]] && \
     [[ -d "./sauce_scripts" && \
        -d "./compose_files" && \
        -d "./sauce_scripts_baked_into_docker_image" && \
        -f "./compose_files/docker-compose.yaml" ]]; then
      # Confirmed: we are in the correct docker/ directory
      echo "✅ Running inside valid docker/ directory."
      export PROJECT_ROOT="$(dirname "$PWD")"
    
  # Last resort: check if we can find commonlib.sh relative to current location
  elif [[ -f "./docker/lib/commonlib.sh" ]]; then
    echo "✅ Found docker/lib/commonlib.sh — assuming current directory is project root."
    export PROJECT_ROOT="$PWD"
  fi

  # Attempt to detect Git root
  export GIT_ROOT=$(find_git_root)

  # Nested logic: decide PROJECT_ROOT and validate everything in one flow
  if [[ -n "$GIT_ROOT" && -d "$GIT_ROOT" && -f "$GIT_ROOT/docker/lib/commonlib.sh" ]]; then
    # Git root is valid AND points to a real SD-Forge project
    export PROJECT_ROOT="$GIT_ROOT"
  else
    # No valid Git root — rely on existing PROJECT_ROOT
    # If PROJECT_ROOT unset or empty AND directory does not exist
    if [[ ! -n "$PROJECT_ROOT" && ! -d "$PROJECT_ROOT" ]]; then
        export GIT_ROOT="error"
        export PROJECT_ROOT="error"
    else
      # OVERRIDE GIT_ROOT
      GIT_ROOT=$PROJECT_ROOT
    fi   
  fi
  
  echo "📁 Git root set to: $GIT_ROOT"
  echo "📁 Project root set to: $PROJECT_ROOT" 

}

# find the GIT_ROOT or PROJECT_ROOT (set both variables, source common config first time)
find_project_root

# safely test for commonlib/commoncfg and attempt sourcing it :)
if [[ -f "$GIT_ROOT/docker/lib/commonlib.sh" && -f "$GIT_ROOT/docker/lib/commoncfg.sh" ]]; then
  # DO NOT source the lib again, it is already sourced and it would create infinite loop
  # source the config
  if ! source "$GIT_ROOT/docker/lib/commoncfg.sh"; then
    echo "❌ Failed to source commoncfg.sh." >&2
    echo "   Check sauces archive is installed in project root." >&2
    echo "   Consult README.md custom/cutdown install or file catspeed-cc issue ticket." >&2
    exit 1
  else
    GIT_ROOT=$PROJECT_ROOT
  fi
fi

if [[ "$PROJECT_ROOT" = "error" || "$PROJECT_ROOT" = "error" ]]; then
  echo "❌ Failed to determine valid GIT_ROOT." >&2
  echo "❌ Failed to determine valid PROJECT_ROOT." >&2
  echo "   Neither a Git-controlled SD-Forge repo nor valid PROJECT_ROOT found." >&2
  echo "   Consult README.md or file catspeed-cc issue ticket." >&2
  exit 1
fi

source ${GIT_ROOT}/docker/lib/commonlib.sh

echo "#"
echo "##"
echo "## sd-forge-webui-docker docker-install-sauces.sh script initiated"
echo "##"
echo "## installing all sauce scripts into PATH and ~/.bashrc"
echo "##"
echo "#"

# determine if cuda exists in the path - if not add it
if [[ ":$PATH:" == *":/usr/local/cuda/bin"* ]]; then
    echo "CUDA path is already in PATH"
    export NEW_PATH="/usr/local/cuda/bin"
fi

# Ether way we add add NEW_PATH to PATH
export NEW_PATH="${NEW_PATH}:${GIT_ROOT}/docker/sauce_scripts/"

export NEW_PATH="${NEW_PATH}:${GIT_ROOT}/docker/sauce_scripts/"

if [ "$FDEBUG}" = "true" ]; then
  echo "Current path: [${PATH}]"
  echo "New path: [${NEW_PATH}]"
fi

# Check if already installed
IS_INSTALLED=$(grep -c "# managed by ${CURRENT_REPOSITORY}" ~/.bashrc)

if [ "$FDEBUG}" = "true" ]; then
  # Show exactly what matches
  echo "DEBUG: Matching lines in ~/.bashrc:"
  grep "# managed by  ${CURRENT_REPOSITORY}" ~/.bashrc || echo "  → No matches found"
fi

if (( IS_INSTALLED > 0 )); then
  echo ""
  echo "Warn: Already installed (scripts already in PATH for ${CURRENT_FORK}). Refusing to install again."
  echo "Run '/docker-uninstall-sauces.sh' first if you want to reinstall."
  echo ""
  exit 0
fi

echo "Scripts will only be accessible as user ${USER} (should be root, docker runs as root)"
echo ""
echo "This will write the new PATH and also add export to .bashrc to make it persist across shells and reboots. 'Y' to continue 'n' to exit."
echo ""
confirm_continue



# Function to update FDEBUG in target files
update_fdebug() {
  local value=$1
  find ./docker/lib -type f -name "commonlib.sh" -print0 | xargs -0 sed -i "s|export FDEBUG=[a-zA-Z0-9._]*|export FDEBUG=$value|g"
  echo "FDEBUG set to $value in matching files."
}

echo ""

# Default to 'n' if empty input
REPLY=${REPLY:-n}

while true; do
  read -p "Do you want to enable DEBUG mode? [N/y]: " -n 1 -r
  echo ""

  # Default to 'n' if empty
  REPLY=${REPLY:-n}

  # Check if input is valid (y/Y/n/N)
  if [[ $REPLY =~ ^[YyNn]$ ]]; then
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      FDEBUG=true
      echo "Enabling DEBUG mode..."
      update_fdebug true
    else
      FDEBUG=false
      echo "Disabling DEBUG mode (default)..."
      update_fdebug false
    fi
    break  # Valid input, exit loop
  else
    # Invalid input, prompt again
    echo "Please answer 'y' or 'n'."
  fi
done

# echo the path to the .bashrc
{
  echo "# managed by ${CURRENT_REPOSITORY} BEGIN"
  echo "export PATH=\${PATH}:${NEW_PATH}"
  echo "# managed by ${CURRENT_REPOSITORY} END"
} | tee -a ~/.bashrc > /dev/null

# this is why we need the fully expanded path, to set the PATH :)
export PATH="\${PATH}:${NEW_PATH}"

# Configure the GIT_ROOT (important, required)
#find ./docker -type f -name "*.sh" -print0 | xargs -0 sed -i "s|export GIT_ROOT=\$(find_git_root)|export GIT_ROOT=$GIT_ROOT|g"
echo "export GIT_ROOT=$GIT_ROOT" tee -a ${GIT_ROOT}/docker/lib/commoncfg.sh

# source the modified ~/.bashrc
source ~/.bashrc

echo ""
echo "Installation completed. Please see available scripts by typing 'docker-' and pressing tab"
echo ""
echo "Alternatively, read the documentation (README.md)"
echo ""
