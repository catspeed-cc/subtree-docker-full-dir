#!/bin/bash

# start.sh - SD Forge launcher with debug fallback

set -euo pipefail  # Exit on error, undefined var, pipe failure

# start out in the correct location
cd /app/webui

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
echo "## sd-forge-webui-docker startup script"
echo "##"
echo "## please grab some coffee, this will take some time on first run"
echo "##"
echo "#"

echo "🚀 Starting Stable Diffusion Forge..." >&2
echo "🔧 Args: $*" >&2

# re/install dependencies
re_install_deps "false"

# change back to webui dir so we can launch `launch.py`
# especially here, re_install_deps.sh may change it
cd /app/webui

# KEEP THIS FOR REFERENCE FOR IDIOT (@mooleshacat) :)
# modules/launch_utils.py contains the repos and hashes
#assets_commit_hash = os.environ.get('ASSETS_COMMIT_HASH', "6f7db241d2f8ba7457bac5ca9753331f0c266917")
#huggingface_guess_commit_hash = os.environ.get('', "84826248b49bb7ca754c73293299c4d4e23a548d")
#blip_commit_hash = os.environ.get('BLIP_COMMIT_HASH', "48211a1594f1321b00f14c9f7a5b4813144b2fb9")

# Example: incoming arguments
args=("$@")

# Array to hold filtered arguments
filtered_args=()

# Loop through all arguments
i=0
while [ $i -lt ${#args[@]} ]; do
  arg="${args[$i]}"

  # Check for --server-name=0.0.0.0 (combined form)
  if [[ "$arg" == "--server-name=0.0.0.0" ]]; then
    # Skip this argument (do not add to filtered_args)
    :
  # Check for --server-name followed by 0.0.0.0 (separate arguments)
  elif [[ "$arg" == "--server-name" ]]; then
    # Skip both --server-name and the next argument (assume it's 0.0.0.0)
    ((i++))  # Skip the value
  else
    # Keep the argument
    filtered_args+=("$arg")
  fi

  ((i++))
done

echo "STARTING THE PYTHON APP..."

# Run SD Forge with all passed arguments (no default so far)
# CONFIRMED --server-name=0.0.0.0 is safe as long as docker compose comments are respected / understood.
exec python3 -W "ignore::FutureWarning" -W "ignore::DeprecationWarning" launch.py --server-name=0.0.0.0${PYTHON_ADD_ARG} ${filtered_args[@]}

if [ "$FDEBUG" = true ]; then
  # This will be enabled by future debug flag
  # If we get here, launch.py failed
  echo "❌ SD Forge exited with code $?"
  echo "💡 Debug shell available. Run: docker-compose exec CONTAINER_NAME bash"
  echo "OR run \`docker-stop-containers.sh\` or \`docker-destroy-*.sh\` to stop the container" 
  exec sleep infinity
fi
