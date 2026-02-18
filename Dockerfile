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
COPY pyproject.toml uv.lock README.md LICENSE ${PAV_BASE}/
COPY src/ ${PAV_BASE}/src/
COPY files/ ${PAV_BASE}/files/

RUN pip3 install --no-cache-dir ${PAV_BASE}

# Setup home directory for runtime
RUN files/docker/build_home.sh

# Runtime environment
ENV PATH="${PATH}:${PAV_BASE}/bin"

ENTRYPOINT ["pav3"]
