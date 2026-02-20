# NOTE: This Dockerfile was generated with AI assistance and has not been
# validated with a full end-to-end Docker build. Review carefully before use.
#
# Common pitfalls:
#   - build_deps.sh downloads binaries from external URLs (UCSC, GitHub releases)
#     that may be unavailable or change over time. Pin versions and verify URLs.
#   - The base image (python:3.12-bookworm) must satisfy system library
#     requirements for samtools, minimap2, LRA, and pav3's Python dependencies.
#   - "pip install" resolves pav3 dependencies at build time. Dependency version
#     conflicts (especially snakemake, polars, numpy) can cause silent failures.
#     Run "pav3 --version" in the built image to verify installation.
#   - The ENTRYPOINT is "pav3" (the CLI). If your workflow expects the old PAV2
#     run script, use "files/docker/run" as a compatibility shim instead.

#
# Stage: build binary dependencies
#

FROM python:3.12-bookworm AS build_deps
LABEL pav_stage=build_deps

ENV PAV_BASE=/opt/pav

WORKDIR ${PAV_BASE}

# Binary dependencies (samtools, minimap2, LRA...)
RUN mkdir -p ${PAV_BASE}/files/docker
COPY files/docker/build_deps.sh ${PAV_BASE}/files/docker
RUN files/docker/build_deps.sh
RUN rm -rf files


#
# Stage: pav3
#

FROM python:3.12-bookworm AS pav3
LABEL pav_stage=pav3

ENV PAV_BASE=/opt/pav

LABEL org.jax.becklab.author="Peter Audano<peter.audano@jax.org>"
LABEL org.jax.becklab.name="PAV3"

WORKDIR ${PAV_BASE}

# Copy binary dependencies from build stage
COPY --from=build_deps ${PAV_BASE} ${PAV_BASE}

# Copy project source and install pav3
# Install directly from the local source code in this repository
# This ensures we use the exact code version being built, not any cached
# or PyPI version
COPY pyproject.toml uv.lock README.md LICENSE ${PAV_BASE}/
COPY src/ ${PAV_BASE}/src/
COPY files/ ${PAV_BASE}/files/

# Install from local source (not PyPI)
# Using "." ensures pip installs from the current directory (${PAV_BASE})
RUN LOCAL_VERSION=$(grep -m1 '^__version__' src/pav3/__init__.py | cut -d"'" -f2) && \
    pip3 install --no-cache-dir . && \
    INSTALLED_VERSION=$(python3 -c "import pav3; print(pav3.__version__)") && \
    if [ "$LOCAL_VERSION" != "$INSTALLED_VERSION" ]; then \
        echo "ERROR: version mismatch - local=$LOCAL_VERSION installed=$INSTALLED_VERSION" >&2; \
        exit 1; \
    fi && \
    echo "✓ Version verified: $INSTALLED_VERSION (matches local source)"

# Patch agglovar's Float32 map_elements calls to use Float64.
# Polars >= 1.38 rejects Python float (Float64) values when return_dtype=pl.Float32
# is used in map_elements. agglovar's overlap join code triggers this during variant
# merging. This patch changes the two map_elements return_dtype declarations and
# their corresponding null-literal casts from Float32 to Float64.
RUN AGGLOVAR_OVERLAP=$(python3 -c "import agglovar.pairwise.overlap._overlap as m; print(m.__file__)") && \
    sed -i 's/return_dtype=pl\.Float32/return_dtype=pl.Float64/g' "$AGGLOVAR_OVERLAP" && \
    sed -i 's/pl\.lit(None)\.cast(pl\.Float32)/pl.lit(None).cast(pl.Float64)/g' "$AGGLOVAR_OVERLAP" && \
    find "$(dirname "$AGGLOVAR_OVERLAP")/__pycache__" -name "*.pyc" -delete 2>/dev/null || true && \
    python3 -c "import importlib; import agglovar.pairwise.overlap._overlap as m; importlib.reload(m); print('✓ Patched agglovar overlap: Float32 -> Float64 in map_elements')"

# Patch agglovar's seqmatch.py to return float instead of int in match_prop().
# When sequences are shorter than jaccard_kmer, match_prop returns 1 or 0 (int),
# which Polars >= 1.38 rejects when building a Float64 Series via map_elements.
# This patch changes "return 1 if ... else 0" to "return 1.0 if ... else 0.0".
RUN AGGLOVAR_SEQMATCH=$(python3 -c "import agglovar.seqmatch as m; print(m.__file__)") && \
    sed -i 's/return 1 if seq_a\.upper() == seq_b\.upper() else 0\s*$/return 1.0 if seq_a.upper() == seq_b.upper() else 0.0/' "$AGGLOVAR_SEQMATCH" && \
    grep -q 'return 1\.0 if seq_a\.upper() == seq_b\.upper() else 0\.0' "$AGGLOVAR_SEQMATCH" || { echo "ERROR: seqmatch patch failed" >&2; exit 1; } && \
    find "$(dirname "$AGGLOVAR_SEQMATCH")/__pycache__" -name "*.pyc" -delete 2>/dev/null || true && \
    python3 -c "import importlib; import agglovar.seqmatch as m; importlib.reload(m); print('✓ Patched agglovar seqmatch: int -> float in match_prop()')"

# Verify the installation works by exercising the scoring code path.
# This catches Float32/Float64 type mismatches in map_elements calls.
RUN python3 -c "\
import polars as pl; \
import numpy as np; \
from pav3.align.score import get_score_model; \
model = get_score_model(None); \
ops = pl.DataFrame({'align_ops': [{'op_code': [7, 8], 'op_len': [1000, 5]}]}); \
result = model.score_align_table(ops); \
assert result.dtype == pl.Float64, f'Unexpected dtype: {result.dtype}'; \
assert len(result) == 1 and result[0] is not None; \
print('✓ Installation verified: scoring code path works correctly')"

# Verify the seqmatch patch: match_prop must return float, not int.
# This catches the Int64/Float64 mismatch in map_elements calls.
RUN python3 -c "\
from agglovar.seqmatch import MatchScoreModel; \
m = MatchScoreModel(); \
r = m.match_prop('A', 'A'); \
assert isinstance(r, float), f'match_prop returned {type(r).__name__}, expected float'; \
r = m.match_prop('A', 'T'); \
assert isinstance(r, float), f'match_prop returned {type(r).__name__}, expected float'; \
print('✓ Seqmatch verified: match_prop returns float')"

# Setup home directory for runtime
RUN files/docker/build_home.sh

# Runtime environment
# NOTE: When running as a non-root user with --user, set -e HOME=/home/default
# to allow Snakemake to write cache files. Without this, Snakemake will attempt
# to write to /.cache and fail with a permission error.
ENV PATH="${PATH}:${PAV_BASE}/bin"

ENTRYPOINT ["pav3"]
