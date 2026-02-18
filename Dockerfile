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
RUN pip3 install --no-cache-dir .

# Verify the installation is from local source by checking for a known fix
# The score_op_arr method should return float (not numpy float64)
RUN python3 -c "import inspect; from pav3.align.score import ScoreModel; \
    src = inspect.getsource(ScoreModel.score_op_arr); \
    assert 'return float(' in src, 'Installation verification failed: expected Float32/Float64 fix not found'; \
    print('✓ Installation verified: code is from local repository')"

# Setup home directory for runtime
RUN files/docker/build_home.sh

# Runtime environment
# NOTE: When running as a non-root user with --user, set -e HOME=/home/default
# to allow Snakemake to write cache files. Without this, Snakemake will attempt
# to write to /.cache and fail with a permission error.
ENV PATH="${PATH}:${PAV_BASE}/bin"

ENTRYPOINT ["pav3"]
