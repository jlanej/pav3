#!/usr/bin/env python3
"""Summarize PAV3 variant calling results from an output directory.

NOTE: AI-generated script. Review before use.

Reads VCF and BED output files produced by pav3 and prints a concise
summary of structural variants, indels, and SNVs found in the run.

Usage:
    python tests/summarize_results.py <output_dir>

Common pitfalls:
    - This script parses VCF INFO fields by splitting on ";" and "=". Non-standard
      or multi-value INFO entries may be silently dropped. Verify against bcftools
      stats for authoritative counts.
    - gzip.open may fail on bgzipped VCFs produced by htslib. If you see
      "not in gzip format" errors, use pysam or bcftools to decompress first.
    - SVLEN may be absent for SNVs or symbolic alleles. The length summary only
      covers records that include a numeric SVLEN.
    - The file-type categorization uses substring matching on the filename (e.g.
      ".vcf" anywhere in the name). Rename collisions (e.g. "vcf_index.txt") would
      be miscategorized.
"""

import argparse
import gzip
import os
import sys
from collections import Counter
from pathlib import Path


def read_vcf_records(vcf_path: Path) -> list[dict]:
    """Read variant records from a VCF file (plain or gzipped)."""

    records = []
    opener = gzip.open if str(vcf_path).endswith('.gz') else open

    with opener(vcf_path, 'rt') as fh:
        for line in fh:
            if line.startswith('#'):
                continue

            fields = line.rstrip('\n').split('\t')

            if len(fields) < 8:
                continue

            info = {}
            for entry in fields[7].split(';'):
                if '=' in entry:
                    key, val = entry.split('=', 1)
                    info[key] = val
                else:
                    info[entry] = True

            records.append({
                'chrom': fields[0],
                'pos': int(fields[1]),
                'id': fields[2],
                'ref': fields[3],
                'alt': fields[4],
                'qual': fields[5],
                'filter': fields[6],
                'info': info,
            })

    return records


def summarize_vcf(vcf_path: Path) -> dict:
    """Return a summary dict for one VCF file."""

    records = read_vcf_records(vcf_path)
    sv_type_counts = Counter()
    sv_lengths = []

    for rec in records:
        svtype = rec['info'].get('SVTYPE', 'UNKNOWN')
        sv_type_counts[svtype] += 1

        svlen = rec['info'].get('SVLEN')
        if svlen is not None:
            try:
                sv_lengths.append(abs(int(svlen)))
            except ValueError:
                pass

    return {
        'file': vcf_path.name,
        'total': len(records),
        'by_type': dict(sv_type_counts),
        'sv_lengths': sv_lengths,
    }


def find_output_files(output_dir: Path) -> dict:
    """Categorise output files by extension."""

    categories = {
        'vcf': [],
        'bed': [],
        'tsv': [],
        'other': [],
    }

    for root, _dirs, files in os.walk(output_dir):
        for fname in files:
            fpath = Path(root) / fname
            name_lower = fname.lower()

            if '.vcf' in name_lower:
                categories['vcf'].append(fpath)
            elif '.bed' in name_lower:
                categories['bed'].append(fpath)
            elif '.tsv' in name_lower:
                categories['tsv'].append(fpath)
            else:
                categories['other'].append(fpath)

    return categories


def print_summary(output_dir: Path) -> None:
    """Print a human-readable summary of pav3 results."""

    print('PAV3 Results Summary')
    print('=' * 50)
    print(f'Output directory: {output_dir}')
    print()

    files = find_output_files(output_dir)

    # File counts
    total = sum(len(v) for v in files.values())
    print(f'Total output files: {total}')
    print(f'  VCF files:  {len(files["vcf"])}')
    print(f'  BED files:  {len(files["bed"])}')
    print(f'  TSV files:  {len(files["tsv"])}')
    print(f'  Other:      {len(files["other"])}')
    print()

    # VCF summaries
    if not files['vcf']:
        print('No VCF files found.')
        return

    print('Variant Summaries')
    print('-' * 50)

    for vcf_path in sorted(files['vcf']):
        try:
            summary = summarize_vcf(vcf_path)
        except Exception as exc:
            print(f'  {vcf_path.name}: ERROR reading file ({exc})')
            continue

        print(f'\n  {summary["file"]}')
        print(f'    Total records: {summary["total"]}')

        if summary['by_type']:
            print('    By type:')
            for svtype in sorted(summary['by_type']):
                print(f'      {svtype:12s} {summary["by_type"][svtype]:>6d}')

        if summary['sv_lengths']:
            lengths = summary['sv_lengths']
            print(f'    SV lengths (n={len(lengths)}):')
            print(f'      min:    {min(lengths):>10,d} bp')
            print(f'      max:    {max(lengths):>10,d} bp')
            print(f'      median: {sorted(lengths)[len(lengths) // 2]:>10,d} bp')

    print()
    print('=' * 50)
    print('Summary complete.')


def main():
    parser = argparse.ArgumentParser(
        description='Summarize PAV3 variant calling results.',
    )
    parser.add_argument(
        'output_dir',
        type=Path,
        help='Path to the pav3 output directory.',
    )
    args = parser.parse_args()

    if not args.output_dir.is_dir():
        print(f'Error: {args.output_dir} is not a directory', file=sys.stderr)
        sys.exit(1)

    print_summary(args.output_dir)


if __name__ == '__main__':
    main()
