# GitHub Actions Workflows

This directory contains CI/CD workflows for the PAV3 project.

## Workflows

### `docker-integration.yml`
**Status:** AI-generated, for testing purposes

Automated integration testing workflow that:
- Builds the PAV3 Docker image
- Runs the pipeline on a minimal test dataset
- Validates VCF outputs
- Uploads results as CI artifacts

**Triggers:** Push to main/dev branches, pull requests, manual dispatch

### `docker-publish.yml`
**Status:** ⚠️ AI-GENERATED - TESTING ONLY ⚠️

**IMPORTANT WARNING:** This workflow and the Docker images it produces were generated via AI-assisted prompts for **TESTING AND DEVELOPMENT PURPOSES ONLY**.

The images have **NOT** been fully validated for production use. The Dockerfile, dependency versions, and runtime configuration may contain errors or omissions.

**DO NOT:**
- Use these images in production environments
- Publish scientific results based on these images
- Recommend these images to users without thorough validation

**Features:**
- Builds and publishes Docker images to GitHub Container Registry (ghcr.io)
- Manual trigger only (workflow_dispatch) to prevent accidental publishes
- Tags images with `-testing` suffix by default
- Includes AI-generation warnings in image labels and metadata

**Before Use:**
1. Review and validate the Dockerfile thoroughly
2. Test the image end-to-end with real data
3. Verify all dependencies and versions
4. Consult with PAV3 maintainers

**Pull Published Images:**
```bash
docker pull ghcr.io/jlanej/pav3:<branch>-testing
```

**Run the Image:**
```bash
docker run --rm ghcr.io/jlanej/pav3:<branch>-testing --version
```

## Development Notes

- All workflows include extensive inline documentation of common pitfalls
- Docker builds compile samtools, minimap2, and LRA from source (~20 minutes)
- GitHub Actions runners have ~14 GB disk and ~7 GB RAM limits
- Test data is sized to stay well within CI resource constraints

## Contributing

When modifying workflows:
1. Validate YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('workflow.yml'))"`
2. Test changes in a fork first
3. Document any new environment variables or secrets required
4. Update this README with any new workflows or significant changes
