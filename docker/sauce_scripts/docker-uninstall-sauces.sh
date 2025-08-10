#!/bin/bash

# docker-uninstall-sauces.sh: remove sauces from path & ~/.bashrc

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
echo "## sd-forge-webui-docker docker-uninstall-sauces.sh script initiated"
echo "##"
echo "## UNinstalling all sauce scripts from PATH and ~/.bashrc"
echo "##"
echo "#"

ADD_TO_PATH=${GIT_ROOT}/docker/sauce_scripts/

if [ "$FDEBUG" = true ]; then
  echo "[DEBUG] ADD_TO_PATH: [${ADD_TO_PATH}]"
  echo "Current path: [${PATH}]"
fi
NEW_PATH="${PATH}:${ADD_TO_PATH}"
if [ "$FDEBUG" = true ]; then
  echo "Final path to add: [${NEW_PATH}]"
fi

echo ""
echo "This will remove the sauce scripts from the PATH and ~/.bashrc. 'Y' to continue 'n' to exit."
echo ""
confirm_continue

# Escape NEW_PATH for safe use in sed (escape . * + ? ^ $ [] $$
escape_for_sed() {
  echo "$1" | sed 's/[.[\*^$()+?{|]/\\&/g'
}

export NEW_PATH_ESCAPED=$(escape_for_sed "$NEW_PATH")

sed -i "/# managed by ${CURRENT_REPOSITORY} BEGIN/,/# managed by ${CURRENT_REPOSITORY} END/d" ~/.bashrc   

# Update current session's PATH (remove the entry)
export PATH=$(echo ":$PATH:" | sed -E "s#:${NEW_PATH}:#:#g" | sed 's#^:##; s#:$##')

# source the modified ~/.bashrc
source ~/.bashrc

echo "Uninstalled: $NEW_PATH removed from PATH and ~/.bashrc"

echo ""
echo "Uninstallation completed."
echo ""
