# PAV3 Mini Test Dataset

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
├── samples.tsv                # Sample manifest
├── config.json                # PAV3 config (JSON format)
├── config.yaml                # PAV3 config (YAML format)
└── README.md                  # This file
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
