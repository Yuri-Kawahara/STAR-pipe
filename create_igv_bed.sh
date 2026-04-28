#!/bin/bash
###############################################################################

# IGV用BEDファイル作成スクリプト（マウス GRCm39 / GENCODE M38）

# 

# 用途: GTFファイルからIGV表示用のBEDファイルを2種類作成する

# - BED6: 遺伝子レベル（高速検索用）

# - BED12: 転写産物レベル（エキソン/イントロン構造の可視化用）

# 

# 使用方法:

# bash create_igv_bed_mouse.sh

# 

# 出力:

# mouse_genes.bed        - 遺伝子レベル BED6

# mouse_transcripts.bed  - 転写産物レベル BED12（IGV推奨）

# 

# IGVでの使い方:

# 1. Genomes > Load Genome from File → GRCm39.primary_assembly.genome.fa

# 2. File > Load from File → mouse_transcripts.bed

# 3. 遺伝子名で検索可能（例: Trp53, Myc）

###############################################################################

### — 設定項目（必要に応じて変更） —

REF_DIR=~/Reference/mouse/
GTF=”${REF_DIR}gencode.vM38.primary_assembly.annotation.gtf”

OUTPUT_DIR=”${REF_DIR}igv/”
GENE_BED=”${OUTPUT_DIR}mouse_genes.bed”
TRANSCRIPT_BED=”${OUTPUT_DIR}mouse_transcripts.bed”

### — 準備 —

echo “======================================================”
echo “IGV BED File Creation (Mouse GRCm39 / GENCODE M38)”
echo “======================================================”

mkdir -p ${OUTPUT_DIR}

# GTFファイルの存在確認

if [ ! -f “${GTF}” ]; then
echo “ERROR: GTF file not found: ${GTF}”
echo “先にリファレンスのダウンロードとgunzipを行ってください。”
exit 1
fi

echo “GTF: ${GTF}”
echo “Output directory: ${OUTPUT_DIR}”
echo “”

### — Step 1: 遺伝子レベル BED6 —

echo “Step 1: Creating gene-level BED6…”

awk -F’\t’ ‘BEGIN {OFS=”\t”}
/^#/ { next }
$3 == “gene” {
match($9, /gene_id “([^”]+)”/, gene_id_arr);
gene_id = gene_id_arr[1];
if (match($9, /gene_name “([^”]+)”/, gene_name_arr)) {
gene_name = gene_name_arr[1];
} else {
gene_name = gene_id;
}
print $1, $4-1, $5, gene_name, “1000”, $7;
}’ “${GTF}” | sort -k1,1 -k2,2n > “${GENE_BED}”

if [ $? -eq 0 ]; then
NUM_GENES=$(wc -l < “${GENE_BED}”)
echo “✓ Gene-level BED6 created: ${GENE_BED} (${NUM_GENES} genes)”
else
echo “ERROR: BED6 creation failed.”
exit 1
fi

### — Step 2: 転写産物レベル BED12 —

echo “Step 2: Creating transcript-level BED12 (this may take a few minutes)…”

python3 - <<‘PYTHON_SCRIPT’ “${GTF}” “${TRANSCRIPT_BED}”
import sys
from collections import defaultdict

gtf_file = sys.argv[1]
bed_file = sys.argv[2]

# 転写産物ごとにエキソン情報を格納

transcripts = defaultdict(lambda: {
‘chr’: ‘’, ‘strand’: ‘’, ‘exons’: [],
‘gene_name’: ‘’, ‘start’: float(‘inf’), ‘end’: 0
})

print(”  Reading GTF…”, flush=True)
with open(gtf_file, ‘r’) as f:
for line in f:
if line.startswith(’#’):
continue
fields = line.strip().split(’\t’)
if len(fields) < 9:
continue

```
    feature = fields[2]
    if feature not in ['transcript', 'exon']:
        continue

    chrom  = fields[0]
    start  = int(fields[3]) - 1  # GTFは1-based → BEDは0-based
    end    = int(fields[4])
    strand = fields[6]
    attrs  = fields[8]

    # transcript_id と gene_name を抽出
    tid       = None
    gene_name = None
    for attr in attrs.split(';'):
        attr = attr.strip()
        if attr.startswith('transcript_id'):
            tid = attr.split('"')[1]
        elif attr.startswith('gene_name'):
            gene_name = attr.split('"')[1]

    if not tid:
        continue

    t = transcripts[tid]
    t['chr']    = chrom
    t['strand'] = strand
    t['start']  = min(t['start'], start)
    t['end']    = max(t['end'],   end)
    if gene_name and not t['gene_name']:
        t['gene_name'] = gene_name

    if feature == 'exon':
        t['exons'].append((start, end))
```

print(”  Writing BED12…”, flush=True)
count = 0
with open(bed_file, ‘w’) as out:
for tid, d in sorted(transcripts.items()):
if not d[‘exons’]:
continue

```
    exons      = sorted(d['exons'])
    tx_start   = d['start']
    tx_end     = d['end']
    name       = d['gene_name'] if d['gene_name'] else tid
    block_sizes  = ','.join([str(e - s) for s, e in exons])
    block_starts = ','.join([str(s - tx_start) for s, e in exons])

    out.write(
        f"{d['chr']}\t{tx_start}\t{tx_end}\t{name}\t1000\t{d['strand']}\t"
        f"{tx_start}\t{tx_end}\t0,0,0\t{len(exons)}\t"
        f"{block_sizes}\t{block_starts}\n"
    )
    count += 1
```

print(f”  Done. {count} transcripts written.”)
PYTHON_SCRIPT

if [ $? -eq 0 ]; then
NUM_TX=$(wc -l < “${TRANSCRIPT_BED}”)
echo “✓ Transcript-level BED12 created: ${TRANSCRIPT_BED} (${NUM_TX} transcripts)”
else
echo “ERROR: BED12 creation failed.”
exit 1
fi

### — 完了サマリー —

echo “”
echo “======================================================”
echo “✓ All BED files created successfully!”
echo “======================================================”
echo “  Gene-level BED6  : ${GENE_BED}”
echo “  Transcript BED12 : ${TRANSCRIPT_BED}   ← IGVにはこちらを推奨”
echo “”
echo “IGVでの読み込み手順:”
echo “  1. Genomes > Load Genome from File”
echo “     → GRCm39.primary_assembly.genome.fa”
echo “  2. File > Load from File”
echo “     → ${TRANSCRIPT_BED}”
echo “  3. 遺伝子名で検索（例: Trp53, Myc, Cd8a）”
echo “======================================================”