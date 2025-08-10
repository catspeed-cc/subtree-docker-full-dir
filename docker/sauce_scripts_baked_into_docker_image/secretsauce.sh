#!/usr/bin/env bash

# secretsauce.sh - a script that is copied to the container to be executed via "docker exec" by end user to reinstall container(s) dependencies

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

  PROJECT_ROOT=""
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Check if we are inside the 'docker' directory (current path contains /docker)
  if [[ "$PWD" == *"/docker" || "$PWD" == *"/docker/"* ]]; then
    if [[ -d "./sauce_scripts" && \
          -d "./compose_files" && \
          -d "./sauce_scripts_baked_into_docker_image" && \
          -f "./compose_files/docker-compose.yaml" ]]; then
        # Confirmed: we are in the correct docker/ directory
        echo "✅ Running inside valid docker/ directory."
        PROJECT_ROOT="$(dirname "$PWD")"
    else
        echo "❌ Directory structure incomplete: not a valid SD-Forge docker/ directory." >&2
        exit 1
    fi

  # Last resort: check if we can find commonlib.sh relative to current location
  elif [[ -f "./docker/lib/commonlib.sh" ]]; then
    echo "✅ Found docker/lib/commonlib.sh — assuming current directory is project root."
    PROJECT_ROOT="$PWD"
  else
    # No valid context found
    echo "❌ Error: Could not locate SD-Forge project structure." >&2
    echo "Please ensure the project contains the './docker' directory" >&2
    echo "Refer to the README.md RE: custom cut down install (you need the sauces archive)" >&2
    exit 1
  fi

  # If we get here, we are either in an SD-Forge repo or a custom/cutdown install

  # Attempt to detect Git root
  export GIT_ROOT=$(find_git_root)

  # Nested logic: decide PROJECT_ROOT and validate everything in one flow
  if [[ -n "$GIT_ROOT" && -d "$GIT_ROOT" && -f "$GIT_ROOT/docker/lib/commonlib.sh" ]]; then
    # Git root is valid AND points to a real SD-Forge project
    PROJECT_ROOT="$GIT_ROOT"
  else
    # No valid Git root — rely on existing PROJECT_ROOT
    if [[ -n "$PROJECT_ROOT" && -d "$PROJECT_ROOT" ]]; then
        echo "❌ Failed to determine valid GIT_ROOT." >&2
        echo "❌ Failed to determine valid PROJECT_ROOT." >&2
        echo "   Neither a Git-controlled SD-Forge repo nor valid PROJECT_ROOT found." >&2
        echo "   Consult README.md or file catspeed-cc issue ticket." >&2
        exit 1
    fi
    # OVERRIDE GIT_ROOT
    GIT_ROOT=$PROJECT_ROOT    
  fi
  
  # Export and report (only reached if validation passed)
  export PROJECT_ROOT
  echo "📁 Git root set to: $GIT_ROOT"
  echo "📁 Project root set to: $PROJECT_ROOT" 

}

# find the GIT_ROOT or PROJECT_ROOT (set both variables, source common config first time)
find_project_root

# safely test for commonlib/commoncfg and attempt sourcing it :)
if [[ -f "$GIT_ROOT/docker/lib/commonlib.sh" && -f "$GIT_ROOT/docker/lib/commoncfg.sh" ]]; then
  # source the library
  if ! source "$GIT_ROOT/docker/lib/commonlib.sh"; then
    echo "❌ Failed to source commonlib.sh." >&2
    echo "   Found Git-controlled SD-Forge repo or valid PROJECT_ROOT but failed to source critical libs." >&2
    echo "   Check sauces archive is installed in project root." >&2
    echo "   Consult README.md custom/cutdown install or file catspeed-cc issue ticket." >&2
    exit 1
  fi
  # source the config
  if ! source "$GIT_ROOT/docker/lib/commoncfg.sh"; then
    echo "❌ Failed to source commoncfg.sh." >&2
    echo "   Found Git-controlled SD-Forge repo or valid PROJECT_ROOT but failed to source critical libs." >&2
    echo "   Check sauces archive is installed in project root." >&2
    echo "   Consult README.md custom/cutdown install or file catspeed-cc issue ticket." >&2
    exit 1
  fi
fi

echo "#"
echo "##"
echo "## sd-forge-webui-docker secretsauce script"
echo "##"
echo "## reinstalling all possible dependencies while container is running"
echo "## please grab some coffee, this will take some time on first run"
echo "##"
echo "#"

echo ""
# Debug: show paths
echo "📘 Script name: $SCRIPT_NAME"
echo "📁 Absolute script path: $ABS_SCRIPT_PATH"
echo "🔗 Relative script path: $REL_SCRIPT_PATH"
echo "📁 Absolute dir: $ABS_SCRIPT_DIR"
echo "🔗 Relative dir: $REL_SCRIPT_DIR"
echo "💻 Running from: $PWD"
echo ""
echo ""

echo "🚀 Starting Stable Diffusion Forge..." >&2
echo "🔧 Args: $*" >&2

# install dependencies
re_install_deps "true"

# change back to webui dir (good practice)
cd /app/webui
