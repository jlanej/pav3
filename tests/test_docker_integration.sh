#!/usr/bin/env bash
#
# NOTE: AI-generated integration test. Review before use.
#
# Integration test for pav3 Docker image.
#
# Builds the Docker image, runs pav3 on the mini test dataset, and validates
# that output files are produced. Generates a summary report of results.
#
# Usage:
#   tests/test_docker_integration.sh [--keep]
#
# Options:
#   --keep   Do not remove the working directory after the test.
#
# Prerequisites:
#   - Docker installed and accessible
#   - Run from the repository root directory
#
# Common pitfalls:
#   - The Docker build downloads external binaries (samtools, minimap2, LRA,
#     bedToBigBed). Network restrictions or URL changes will cause build
#     failures. Check build_deps.sh if the build fails during downloads.
#   - The test data region (~2 Mb of chr17) is small. PAV may produce few or
#     no variants depending on aligner behavior at region boundaries. An empty
#     VCF is not necessarily a bug—inspect alignment tables to diagnose.
#   - VCF field names (SVTYPE, SVLEN) are assumed by the summary grep commands.
#     If pav3 changes its VCF INFO keys, the counts will silently report 0.
#   - The "--user" Docker flag maps host UID/GID into the container. On some
#     systems (rootless Docker, SELinux) this may cause permission errors. Try
#     removing the --user flag or adding ":z" to the bind mount if you see
#     "permission denied" on output files.
#   - Snakemake may re-run rules unnecessarily if file timestamps are not
#     preserved during the copy step. The --rerun-triggers=mtime flag in pav3
#     mitigates this, but be aware of it when debugging unexpected reruns.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DATA="${REPO_ROOT}/tests/test_data"
IMAGE_NAME="pav3-test"
WORK_DIR=""
KEEP=false

# Parse arguments
for arg in "$@"; do
    case ${arg} in
        --keep) KEEP=true ;;
        *) echo "Unknown argument: ${arg}"; exit 1 ;;
    esac
done

cleanup() {
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" && "${KEEP}" == "false" ]]; then
        echo "Cleaning up working directory: ${WORK_DIR}"
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT

log() {
    echo ""
    echo "=========================================="
    echo "  $1"
    echo "=========================================="
    echo ""
}

fail() {
    echo "FAIL: $1" >&2
    exit 1
}


# ---------------------------------------------------------------------------
# Step 1: Build Docker image
# ---------------------------------------------------------------------------
log "Step 1: Building Docker image"

docker build -t "${IMAGE_NAME}" "${REPO_ROOT}" || fail "Docker build failed"

echo "Docker image built successfully: ${IMAGE_NAME}"


# ---------------------------------------------------------------------------
# Step 2: Verify pav3 is installed in the image
# ---------------------------------------------------------------------------
log "Step 2: Verifying pav3 installation"

PAV_VERSION=$(docker run --rm "${IMAGE_NAME}" --version 2>&1) \
    || fail "pav3 --version failed"
echo "pav3 version: ${PAV_VERSION}"


# ---------------------------------------------------------------------------
# Step 3: Set up working directory with test data
# ---------------------------------------------------------------------------
log "Step 3: Setting up working directory"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pav3_integration_XXXXXX")
echo "Working directory: ${WORK_DIR}"

# Copy test data into the working directory
cp -r "${TEST_DATA}/ref" "${WORK_DIR}/"
cp -r "${TEST_DATA}/assemblies" "${WORK_DIR}/"
cp "${TEST_DATA}/pav.json" "${WORK_DIR}/"
cp "${TEST_DATA}/assemblies.tsv" "${WORK_DIR}/"

echo "Test data staged in ${WORK_DIR}"


# ---------------------------------------------------------------------------
# Step 4: Run pav3 batch via Docker
# ---------------------------------------------------------------------------
log "Step 4: Running pav3 batch"

docker run --rm \
    -v "${WORK_DIR}:${WORK_DIR}" \
    --user "$(id -u):$(id -g)" \
    --workdir "${WORK_DIR}" \
    "${IMAGE_NAME}" \
    batch --cores 4 --keep-going \
    || fail "pav3 batch failed"

echo "pav3 batch completed"


# ---------------------------------------------------------------------------
# Step 5: Validate output files exist
# ---------------------------------------------------------------------------
log "Step 5: Validating output"

PASS=true

# Check for VCF output
VCF_FILES=$(find "${WORK_DIR}" -name "*.vcf.gz" 2>/dev/null || true)
if [[ -z "${VCF_FILES}" ]]; then
    echo "WARNING: No VCF files found"
    PASS=false
else
    echo "VCF files found:"
    echo "${VCF_FILES}" | sed 's/^/  /'
fi

# Check for BED output
BED_FILES=$(find "${WORK_DIR}" -name "*.bed.gz" -o -name "*.bed" 2>/dev/null || true)
if [[ -n "${BED_FILES}" ]]; then
    echo "BED files found:"
    echo "${BED_FILES}" | head -20 | sed 's/^/  /'
fi

# Check for alignment tables
ALIGN_FILES=$(find "${WORK_DIR}" -name "*align*" -name "*.tsv.gz" 2>/dev/null || true)
if [[ -n "${ALIGN_FILES}" ]]; then
    echo "Alignment tables found:"
    echo "${ALIGN_FILES}" | head -10 | sed 's/^/  /'
fi


# ---------------------------------------------------------------------------
# Step 6: Generate summary report
# ---------------------------------------------------------------------------
log "Step 6: Generating summary report"

REPORT="${WORK_DIR}/integration_test_report.txt"

{
    echo "PAV3 Integration Test Report"
    echo "============================"
    echo ""
    echo "Date:    $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "Version: ${PAV_VERSION}"
    echo "Data:    tests/test_data (chr17:9958130-12017414, NA19240)"
    echo ""

    echo "Output Files"
    echo "------------"

    FILE_COUNT=$(find "${WORK_DIR}" -type f | wc -l)
    echo "Total files produced: ${FILE_COUNT}"
    echo ""

    VCF_COUNT=$(echo "${VCF_FILES}" | grep -c '.vcf.gz' 2>/dev/null || echo 0)
    echo "VCF files: ${VCF_COUNT}"

    if [[ -n "${VCF_FILES}" ]]; then
        echo ""
        echo "Variant Summary"
        echo "---------------"

        for vcf in ${VCF_FILES}; do
            vcf_name=$(basename "${vcf}")
            echo ""
            echo "  File: ${vcf_name}"

            # Count variants by type using zgrep (skip header lines)
            total=$(zgrep -cv '^#' "${vcf}" 2>/dev/null || echo 0)
            echo "  Total variant records: ${total}"

            snv=$(zgrep -v '^#' "${vcf}" 2>/dev/null | grep -c 'SVTYPE=SNV' 2>/dev/null || echo 0)
            indel_ins=$(zgrep -v '^#' "${vcf}" 2>/dev/null | grep -c 'SVTYPE=INS' 2>/dev/null || echo 0)
            indel_del=$(zgrep -v '^#' "${vcf}" 2>/dev/null | grep -c 'SVTYPE=DEL' 2>/dev/null || echo 0)
            inv=$(zgrep -v '^#' "${vcf}" 2>/dev/null | grep -c 'SVTYPE=INV' 2>/dev/null || echo 0)

            echo "  SNVs:       ${snv}"
            echo "  Insertions: ${indel_ins}"
            echo "  Deletions:  ${indel_del}"
            echo "  Inversions: ${inv}"
        done
    fi

    echo ""
    echo "Directory Structure"
    echo "-------------------"
    find "${WORK_DIR}" -type d | sed "s|${WORK_DIR}|.|" | sort | head -40

} | tee "${REPORT}"


# ---------------------------------------------------------------------------
# Step 7: Final result
# ---------------------------------------------------------------------------
log "Test Result"

if [[ "${PASS}" == "true" ]]; then
    echo "PASSED - Integration test completed successfully"
    echo "Report: ${REPORT}"
    exit 0
else
    echo "FAILED - Some expected outputs were not found"
    echo "Report: ${REPORT}"
    exit 1
fi
