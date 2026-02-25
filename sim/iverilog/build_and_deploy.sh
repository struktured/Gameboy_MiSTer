#!/bin/bash
# Build Gameboy core with Quartus and deploy to MiSTer
set -e

PROJ_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
QUARTUS_PROJECT="Gameboy"
MISTER_HOST="${MISTER_HOST:-mister}"
DEPLOY_PATH="/media/fat/_.rbf"

echo "=== Gameboy MiSTer Build & Deploy ==="
echo "Project dir: $PROJ_DIR"

# Check for Quartus
if ! command -v quartus_map &> /dev/null; then
    echo "WARNING: Quartus not found on PATH"
    echo "Skipping FPGA build. To build manually:"
    echo "  cd $PROJ_DIR"
    echo "  quartus_sh --flow compile $QUARTUS_PROJECT"
    exit 0
fi

cd "$PROJ_DIR"

echo ""
echo "--- Quartus Map (Analysis & Synthesis) ---"
quartus_map --read_settings_files=on --write_settings_files=off "$QUARTUS_PROJECT" -c "$QUARTUS_PROJECT"

echo ""
echo "--- Quartus Fit (Place & Route) ---"
quartus_fit --read_settings_files=off --write_settings_files=off "$QUARTUS_PROJECT" -c "$QUARTUS_PROJECT"

echo ""
echo "--- Quartus Assembler ---"
quartus_asm --read_settings_files=off --write_settings_files=off "$QUARTUS_PROJECT" -c "$QUARTUS_PROJECT"

RBF_FILE="output_files/${QUARTUS_PROJECT}.rbf"
if [ ! -f "$RBF_FILE" ]; then
    echo "ERROR: RBF file not found at $RBF_FILE"
    exit 1
fi

echo ""
echo "--- RBF built: $RBF_FILE ---"
echo "Size: $(du -h "$RBF_FILE" | cut -f1)"

# Deploy to MiSTer
if [ -n "$MISTER_HOST" ]; then
    echo ""
    echo "--- Deploying to MiSTer ($MISTER_HOST) ---"
    scp "$RBF_FILE" "root@${MISTER_HOST}:${DEPLOY_PATH}" && \
        echo "Deployed to ${MISTER_HOST}:${DEPLOY_PATH}" || \
        echo "Deploy failed - check MISTER_HOST and connectivity"
fi

echo ""
echo "=== Done ==="
