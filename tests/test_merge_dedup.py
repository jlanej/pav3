"""Tests for post-merge deduplication in merge_haplotypes.

Verifies that near-duplicate variants from the same haplotype do not produce
duplicate records at the same coordinates after merging.
"""

import os
import tempfile

import polars as pl
import pytest

import pav3.workflow.call


@pytest.fixture
def ref_path():
    """Create a minimal reference FASTA + FAI for merge_haplotypes."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.fa', delete=False) as f:
        path = f.name
        f.write('>chr20\nACGT\n')

    with open(path + '.fai', 'w') as f:
        f.write('chr20\t4\t6\t4\t5\n')

    yield path

    os.unlink(path)
    os.unlink(path + '.fai')


def _make_callset(rows):
    """Build a LazyFrame callset from a list of row dicts."""
    return (
        pl.LazyFrame(rows)
        .cast({
            'pos': pl.Int64,
            'end': pl.Int64,
            'varlen': pl.Int64,
            'filter': pl.List(pl.String),
        })
        .with_row_index('_index')
    )


def test_no_duplicate_at_same_coords(ref_path):
    """Variants at the same (chrom, pos, end, varlen) must not appear twice.

    Reproduces the reported bug where a near-duplicate within a haplotype
    causes one copy to merge cross-haplotype (1|1) while the other remains
    as a separate record (.|1) at identical coordinates.
    """
    seq_530 = 'A' * 530
    seq_525 = 'A' * 525

    hap1 = _make_callset([{
        'chrom': 'chr20', 'pos': 31064547, 'end': 31065077,
        'id': 'del_1', 'vartype': 'DEL', 'varlen': 530,
        'ref': 'N', 'alt': '<DEL>', 'seq': seq_530, 'filter': [],
    }])

    hap2 = _make_callset([
        {
            'chrom': 'chr20', 'pos': 31064547, 'end': 31065072,
            'id': 'del_2a', 'vartype': 'DEL', 'varlen': 525,
            'ref': 'N', 'alt': '<DEL>', 'seq': seq_525, 'filter': [],
        },
        {
            'chrom': 'chr20', 'pos': 31064547, 'end': 31065077,
            'id': 'del_2b', 'vartype': 'DEL', 'varlen': 530,
            'ref': 'N', 'alt': '<DEL>', 'seq': seq_530, 'filter': ['LOWQUAL'],
        },
    ])

    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = os.path.join(tmpdir, 'merged.parquet')
        pav3.workflow.call.merge_haplotypes(
            vartype='insdel',
            callsets=((hap1, 'hap1'), (hap2, 'hap2')),
            ref_path=ref_path,
            out_path=out_path,
        )
        df = pl.read_parquet(out_path)

    dup = df.filter(
        (pl.col('pos') == 31064547)
        & (pl.col('end') == 31065077)
        & (pl.col('varlen') == 530)
    )

    assert len(dup) == 1, (
        f'Expected exactly 1 variant at (31064547, 31065077, 530), got {len(dup)}'
    )

    # The retained variant should have the most haplotype sources
    assert len(dup['mg_src'][0]) == 2, (
        'Retained variant should carry sources from both haplotypes'
    )


def test_pass_preferred_over_nonpass(ref_path):
    """When deduplicating, PASS variant (empty filter) is preferred."""
    hap1 = _make_callset([{
        'chrom': 'chr20', 'pos': 100, 'end': 200,
        'id': 'del_1', 'vartype': 'DEL', 'varlen': 100,
        'ref': 'N', 'alt': '<DEL>', 'seq': 'A' * 100, 'filter': [],
    }])

    hap2 = _make_callset([{
        'chrom': 'chr20', 'pos': 100, 'end': 200,
        'id': 'del_2', 'vartype': 'DEL', 'varlen': 100,
        'ref': 'N', 'alt': '<DEL>', 'seq': 'A' * 100, 'filter': ['LOWQUAL'],
    }])

    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = os.path.join(tmpdir, 'merged.parquet')
        pav3.workflow.call.merge_haplotypes(
            vartype='insdel',
            callsets=((hap1, 'hap1'), (hap2, 'hap2')),
            ref_path=ref_path,
            out_path=out_path,
        )
        df = pl.read_parquet(out_path)

    assert len(df) == 1
    assert len(df['mg_src'][0]) == 2
    assert df['filter'].to_list()[0] == []


def test_distinct_variants_not_removed(ref_path):
    """Variants at different positions must not be removed by dedup."""
    hap1 = _make_callset([
        {
            'chrom': 'chr20', 'pos': 100, 'end': 200,
            'id': 'del_1a', 'vartype': 'DEL', 'varlen': 100,
            'ref': 'N', 'alt': '<DEL>', 'seq': 'A' * 100, 'filter': [],
        },
        {
            'chrom': 'chr20', 'pos': 500, 'end': 600,
            'id': 'del_1b', 'vartype': 'DEL', 'varlen': 100,
            'ref': 'N', 'alt': '<DEL>', 'seq': 'C' * 100, 'filter': [],
        },
    ])

    hap2 = _make_callset([{
        'chrom': 'chr20', 'pos': 100, 'end': 200,
        'id': 'del_2', 'vartype': 'DEL', 'varlen': 100,
        'ref': 'N', 'alt': '<DEL>', 'seq': 'A' * 100, 'filter': [],
    }])

    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = os.path.join(tmpdir, 'merged.parquet')
        pav3.workflow.call.merge_haplotypes(
            vartype='insdel',
            callsets=((hap1, 'hap1'), (hap2, 'hap2')),
            ref_path=ref_path,
            out_path=out_path,
        )
        df = pl.read_parquet(out_path)

    assert len(df) == 2, f'Expected 2 distinct variants, got {len(df)}'


def test_nonpass_variants_retained(ref_path):
    """Non-PASS variants at unique positions must still appear in output."""
    hap1 = _make_callset([{
        'chrom': 'chr20', 'pos': 100, 'end': 200,
        'id': 'del_1', 'vartype': 'DEL', 'varlen': 100,
        'ref': 'N', 'alt': '<DEL>', 'seq': 'A' * 100, 'filter': ['LOWQUAL'],
    }])

    hap2 = _make_callset([{
        'chrom': 'chr20', 'pos': 300, 'end': 400,
        'id': 'del_2', 'vartype': 'DEL', 'varlen': 100,
        'ref': 'N', 'alt': '<DEL>', 'seq': 'C' * 100, 'filter': ['LOWQUAL'],
    }])

    with tempfile.TemporaryDirectory() as tmpdir:
        out_path = os.path.join(tmpdir, 'merged.parquet')
        pav3.workflow.call.merge_haplotypes(
            vartype='insdel',
            callsets=((hap1, 'hap1'), (hap2, 'hap2')),
            ref_path=ref_path,
            out_path=out_path,
        )
        df = pl.read_parquet(out_path)

    assert len(df) == 2
    for row in df.iter_rows(named=True):
        assert row['filter'] == ['LOWQUAL']
