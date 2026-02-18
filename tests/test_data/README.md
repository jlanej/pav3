# PAV3 Mini Test Dataset

> **Note**: The integration test script, summary script, pav.json, assemblies.tsv,
> and Dockerfile changes in this PR were generated with AI assistance. They have
> not been validated with a full end-to-end Docker build and pav3 run. Review all
> files carefully before relying on them in CI or production workflows.

This directory contains a minimal test dataset for PAV3 integration testing.

## Source Data

- **Reference**: GRCh38 (GCA_000001405.15)
- **Sample**: NA19240 (HPRC Year 2, v1.0.1)
- **Region**: chr17:9958130-12017414 (~2 Mb)

## Files

```
test_data/
├── ref/
│   └── GRCh38_mini.fa.gz      # Mini reference (target region only)
├── assemblies/
│   └── NA19240/
│       ├── mat.fa.gz          # Maternal contigs overlapping target
│       └── pat.fa.gz          # Paternal contigs overlapping target
├── pav.json                   # PAV3 config (required by pav3)
├── assemblies.tsv             # Assembly table (required by pav3)
├── samples.tsv                # Sample manifest (legacy format)
├── config.json                # Legacy config (JSON format)
├── config.yaml                # Legacy config (YAML format)
└── README.md                  # This file
```

## Running the Integration Test

From the repository root:
```bash
tests/test_docker_integration.sh
```

This builds the Docker image, runs pav3 on this test data, and validates output.
Use `--keep` to preserve the working directory for inspection.

To summarize results from a completed run:
```bash
python tests/summarize_results.py <output_dir>
```

## Reference Coordinates

The mini reference FASTA header includes the full coordinates:
```
>chr17:9958130-12017414
```

This makes it clear that:
- Position 1 in this file = position 9958130 in GRCh38
- Position N in this file = position 9958130 + N - 1 in GRCh38

## Notes

- The reference coordinates in output VCFs will be relative to the extracted region
- Reference offset is stored in config.yaml for coordinate translation if needed
- Generated on: 2026-02-18

## Common Pitfalls

- **Config file names**: pav3 looks for `pav.json` and `assemblies.tsv` by default.
  The legacy `config.json` and `samples.tsv` are kept for reference but are *not*
  used by pav3. If you see "Missing pav.json" errors, check the file names.
- **Column names**: `assemblies.tsv` must use `NAME`, `HAP1`, `HAP2` headers (not
  `SAMPLE`). pav3's `read_assembly_table()` will error on unrecognized column names.
- **Region boundaries**: The mini reference covers only ~2 Mb of chr17. Contigs
  that extend beyond this region may align partially, which can produce edge-effect
  artifacts in variant calls. This is expected for a small test region.
- **Index files**: The `.fai` and `.gzi` index files must stay in sync with their
  corresponding `.fa.gz` files. If you regenerate the FASTA, re-index with
  `samtools faidx`.
- **Docker non-root user**: When running the Docker container with `--user` (non-root),
  you must set the HOME environment variable: `-e HOME=/home/default`. Without this,
  Snakemake will try to write cache files to `/.cache` and fail with a permission error.
