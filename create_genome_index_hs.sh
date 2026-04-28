#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -l s_vmem=32G
#$ -pe def_slot 16
#$ -N build_human_ref
#$ -o logs/build_human_ref.o$JOB_ID
#$ -e logs/build_human_ref.e$JOB_ID

###############################################################################

# ヒトゲノム リファレンス & インデックス作成スクリプト
# 
# 参照: GENCODE v49 / GRCh38
# 
# 処理内容:
# 1. GENCODEからリファレンスファイルをダウンロード
# 2. Salmon decoy-aware インデックスを構築
# 3. STAR ゲノムインデックスを構築
# 4. IGV用 BEDファイルを作成
# 
# カスタム融合遺伝子を追加したい場合:
# → USE_CUSTOM_FUSION=true に変更し、CUSTOM_FUSION_FA を設定してください
# 
# 使用方法（スパコン）:
# qsub build_human_reference.sh
# 
# 使用方法（ローカル）:
# bash build_human_reference.sh

###############################################################################

### ============================================================
### — !! 設定項目 !! —
### ============================================================
BASE_DIR="/home/kawayuri"

# リファレンス保存先ディレクトリ
REF_DIR=${BASE_DIR}/Reference/human/

# Salmon インデックス出力先
SALMON_INDEX=${BASE_DIR}/gdc_reference/salmon/gencode.v49.human_salmon_index/

# STAR インデックス出力先
STAR_INDEX=${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index/

# IGV BED 出力先
IGV_DIR=”${REF_DIR}igv/”

# スレッド数
THREADS=16

# リード長 - 1（STARの –sjdbOverhang に使用）
# 例: 150bpリードなら149、100bpなら99
OVERHANG=149

# — カスタム融合遺伝子オプション —
# 通常解析では false のまま
USE_CUSTOM_FUSION=false
CUSTOM_FUSION_FA=”${REF_DIR}custom_fusion_genes.fa”   # USE_CUSTOM_FUSION=true のときのみ使用

# 検証モード: 融合遺伝子の検出感度テスト用に野生型遺伝子をGTFから除外する
# 通常解析では空欄のまま → EXCLUDE_WILDTYPE_GENES=””
# 検証時は除外したい遺伝子名をスペース区切りで指定
# 例: EXCLUDE_WILDTYPE_GENES=“ASPSCR1 TFE3”
EXCLUDE_WILDTYPE_GENES=””

### ============================================================

set -euo pipefail  # エラー時即終了・未定義変数をエラーに

### — モジュールロード —

echo “Loading modules…”
module use /usr/local/package/modulefiles
module load star
module load salmon

BASE_DIR=$(pwd)
mkdir -p logs

echo “======================================================”
echo “ Human Reference Build”
echo “ GENCODE v49 / GRCh38”
echo “ Custom fusion: ${USE_CUSTOM_FUSION}”
echo “======================================================”

### ============================================================
### Step 1: リファレンスファイルのダウンロード
### ============================================================

echo “”
echo “Step 1: Downloading reference files (GENCODE v49)…”
mkdir -p ${REF_DIR} && cd ${REF_DIR}

# すでにダウンロード済みならスキップ

download_if_missing() {
    local url=$1
    local filename=$(basename ${url%.gz})
    if [ -f “${filename}” ]; then
        echo “  ✓ Already exists (skip): ${filename}”
    else
        echo “  Downloading: $(basename $url)”
        wget -q –show-progress “$url”
        gunzip “$(basename $url)”
        echo “  ✓ Done: ${filename}”
        fi
}

# トランスクリプトームFASTA（Salmon用）

download_if_missing   
https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/gencode.v49.transcripts.fa.gz

# ゲノムFASTA（STAR用 & Salmon decoy用）

download_if_missing   
https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/GRCh38.primary_assembly.genome.fa.gz

# GTF（STAR インデックス & tximport/tximeta用）

download_if_missing   
https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/gencode.v49.primary_assembly.annotation.gtf.gz

echo “✓ All reference files ready.”

### ============================================================
### Step 1.5: 融合遺伝子GTFの作成（USE_CUSTOM_FUSION=true のときのみ）
### ============================================================

if [ “${USE_CUSTOM_FUSION}” = “true” ]; then
echo “”
echo “Step 1.5: Creating fusion gene GTF…”

```
if [ ! -f "${CUSTOM_FUSION_FA}" ]; then
    echo "ERROR: CUSTOM_FUSION_FA not found: ${CUSTOM_FUSION_FA}"
    echo "  カスタム融合遺伝子FASTAを用意してから再実行してください。"
    exit 1
fi

FUSION_GTF="${REF_DIR}fusion_genes.gtf"
BASE_GTF="${REF_DIR}gencode.v49.primary_assembly.annotation.gtf"

# --- 融合遺伝子FASTAの確認 ---
echo "  Custom fusion FASTA: ${CUSTOM_FUSION_FA}"
echo "  Sequences found:"
grep '^>' "${CUSTOM_FUSION_FA}" | sed 's/>/    · /'

# --- FASTAからGTFを生成（awk）---
echo "  Generating fusion_genes.gtf from FASTA..."
awk '
BEGIN { gene_name = ""; sequence = "" }
/^>/ {
    if (gene_name != "" && sequence != "") {
        seq_len = length(sequence);
        printf "%s\tcustom\tgene\t1\t%d\t.\t+\t.\tgene_id \"%s\"; gene_name \"%s\"; gene_biotype \"fusion\";\n",
               gene_name, seq_len, gene_name, gene_name;
        printf "%s\tcustom\ttranscript\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; gene_name \"%s\"; gene_biotype \"fusion\";\n",
               gene_name, seq_len, gene_name, gene_name, gene_name;
        printf "%s\tcustom\texon\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; exon_number \"1\"; gene_name \"%s\"; gene_biotype \"fusion\";\n",
               gene_name, seq_len, gene_name, gene_name, gene_name;
        print "  ✓ Entry created: " gene_name " (" seq_len " bp)" > "/dev/stderr";
    }
    gene_name = $1; sub(/^>/, "", gene_name);
    sequence = "";
}
!/^>/ { gsub(/[[:space:]]/, "", $0); sequence = sequence $0 }
END {
    if (gene_name != "" && sequence != "") {
        seq_len = length(sequence);
        printf "%s\tcustom\tgene\t1\t%d\t.\t+\t.\tgene_id \"%s\"; gene_name \"%s\"; gene_biotype \"fusion\";\n",
               gene_name, seq_len, gene_name, gene_name;
        printf "%s\tcustom\ttranscript\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; gene_name \"%s\"; gene_biotype \"fusion\";\n",
               gene_name, seq_len, gene_name, gene_name, gene_name;
        printf "%s\tcustom\texon\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; exon_number \"1\"; gene_name \"%s\"; gene_biotype \"fusion\";\n",
               gene_name, seq_len, gene_name, gene_name, gene_name;
        print "  ✓ Entry created: " gene_name " (" seq_len " bp)" > "/dev/stderr";
    }
}
' "${CUSTOM_FUSION_FA}" > "${FUSION_GTF}"

echo "  fusion_genes.gtf entries: $(wc -l < ${FUSION_GTF})"

# --- 検証モード: 野生型遺伝子をベースGTFから除外 ---
if [ -n "${EXCLUDE_WILDTYPE_GENES}" ]; then
    echo ""
    echo "  ⚠ 検証モード: 野生型遺伝子を除外 → ${EXCLUDE_WILDTYPE_GENES}"

    # スペース区切りの遺伝子名を grep の正規表現に変換
    # 例: "ASPSCR1 TFE3" → "ASPSCR1|TFE3"
    EXCLUDE_PATTERN=$(echo "${EXCLUDE_WILDTYPE_GENES}" | tr ' ' '|')

    FILTERED_GTF="${REF_DIR}filtered_human.gtf"
    ORIGINAL_COUNT=$(wc -l < "${BASE_GTF}")
    grep -v -E "gene_name \"(${EXCLUDE_PATTERN})\"" "${BASE_GTF}" > "${FILTERED_GTF}"
    FILTERED_COUNT=$(wc -l < "${FILTERED_GTF}")
    echo "  GTF entries: ${ORIGINAL_COUNT} → ${FILTERED_COUNT} (removed $((ORIGINAL_COUNT - FILTERED_COUNT)))"

    MERGE_BASE="${FILTERED_GTF}"
else
    MERGE_BASE="${BASE_GTF}"
fi

# --- ハイブリッドGTFの作成（ベース + 融合遺伝子）---
HYBRID_GTF="${REF_DIR}hybrid_annotation.gtf"
cat "${MERGE_BASE}" "${FUSION_GTF}" > "${HYBRID_GTF}"
echo "  ✓ Hybrid GTF created: ${HYBRID_GTF} ($(wc -l < ${HYBRID_GTF}) entries)"

# 融合遺伝子エントリの確認
echo "  Fusion gene entries in hybrid GTF:"
grep 'gene_biotype "fusion"' "${HYBRID_GTF}" | grep $'\tgene\t' | \
    awk '{match($9, /gene_name "([^"]+)"/, g); print "    · " g[1]}'
```

else
echo “”
echo “Step 1.5: Skipped (USE_CUSTOM_FUSION=false)”
fi

# ### ============================================================

# ### Step 2: Salmon decoy-aware インデックスの構築

# ### ============================================================

# echo “”
# echo “Step 2: Building Salmon decoy-aware index…”

# if [ -d “${SALMON_INDEX}” ] && [ -f “${SALMON_INDEX}/info.json” ]; then
# echo “  ✓ Salmon index already exists. Skipping.”
# else
# mkdir -p ${SALMON_INDEX}

# ```
# # decoyリストを作成（ゲノムの染色体名を抽出）
# echo "  Creating decoy list..."
# grep '^>' GRCh38.primary_assembly.genome.fa \
#     | cut -d ' ' -f 1 \
#     | sed 's/>//' \
#     > decoys.txt
# echo "  Top 3 entries in decoys.txt:"
# head -3 decoys.txt | sed 's/^/    /'

# # カスタム融合遺伝子を追加する場合
# if [ "${USE_CUSTOM_FUSION}" = "true" ]; then
#     if [ ! -f "${CUSTOM_FUSION_FA}" ]; then
#         echo "ERROR: CUSTOM_FUSION_FA not found: ${CUSTOM_FUSION_FA}"
#         exit 1
#     fi
#     echo "  Appending custom fusion sequences..."
#     cat gencode.v49.transcripts.fa "${CUSTOM_FUSION_FA}" \
#         GRCh38.primary_assembly.genome.fa > gentrome_human.fa
# else
#     cat gencode.v49.transcripts.fa \
#         GRCh38.primary_assembly.genome.fa > gentrome_human.fa
# fi

# echo "  Running salmon index (this takes ~15-30 min)..."
# salmon index \
#     -t gentrome_human.fa \
#     -d decoys.txt \
#     -i ${SALMON_INDEX} \
#     -p ${THREADS}

# echo "✓ Salmon index created: ${SALMON_INDEX}"
# ```

# fi

### ============================================================

### Step 3: STAR ゲノムインデックスの構築

### ============================================================

echo “”
echo “Step 3: Building STAR genome index…”

if [ -d “${STAR_INDEX}” ] && [ -f “${STAR_INDEX}/SAindex” ]; then
echo “  ✓ STAR index already exists. Skipping.”
else
mkdir -p ${STAR_INDEX}

```
# カスタム融合遺伝子を追加する場合はハイブリッドFASTAを使用
if [ "${USE_CUSTOM_FUSION}" = "true" ]; then
    if [ ! -f "${CUSTOM_FUSION_FA}" ]; then
        echo "ERROR: CUSTOM_FUSION_FA not found: ${CUSTOM_FUSION_FA}"
        exit 1
    fi
    echo "  Merging genome with custom fusion sequences..."
    cat GRCh38.primary_assembly.genome.fa "${CUSTOM_FUSION_FA}" > hybrid_genome.fa
    GENOME_FA="${REF_DIR}hybrid_genome.fa"
    # Step 1.5 で作成済みのハイブリッドGTFを使用
    ANNOTATION_GTF="${REF_DIR}hybrid_annotation.gtf"
else
    GENOME_FA="${REF_DIR}GRCh38.primary_assembly.genome.fa"
    ANNOTATION_GTF="${REF_DIR}gencode.v49.primary_assembly.annotation.gtf"
fi

echo "  Running STAR genomeGenerate (this takes ~30-60 min)..."
STAR --runMode genomeGenerate \
     --runThreadN ${THREADS} \
     --genomeDir ${STAR_INDEX} \
     --genomeFastaFiles "${GENOME_FA}" \
     --sjdbGTFfile "${ANNOTATION_GTF}" \
     --sjdbOverhang ${OVERHANG} \
     --genomeSAindexNbases 14

echo "✓ STAR index created: ${STAR_INDEX}"
```

fi

### ============================================================

### Step 4: IGV用 BEDファイルの作成

### ============================================================

echo “”
echo “Step 4: Creating IGV BED files…”
mkdir -p ${IGV_DIR}

ANNOTATION_GTF=”${REF_DIR}gencode.v49.primary_assembly.annotation.gtf”
GENE_BED=”${IGV_DIR}human_genes.bed”
TRANSCRIPT_BED=”${IGV_DIR}human_transcripts.bed”

if [ -f “${TRANSCRIPT_BED}” ]; then
echo “  ✓ IGV BED files already exist. Skipping.”
else
# — BED6（遺伝子レベル）—
echo “  Creating gene-level BED6…”
awk -F’\t’ ‘BEGIN {OFS=”\t”}
/^#/ { next }
$3 == “gene” {
match($9, /gene_id “([^”]+)”/, gid);
match($9, /gene_name “([^”]+)”/, gname);
name = (gname[1] != “”) ? gname[1] : gid[1];
print $1, $4-1, $5, name, “1000”, $7;
}’ “${ANNOTATION_GTF}” | sort -k1,1 -k2,2n > “${GENE_BED}”

```
NUM_GENES=$(wc -l < "${GENE_BED}")
echo "  ✓ Gene BED6: ${GENE_BED} (${NUM_GENES} genes)"

# --- BED12（転写産物レベル）---
echo "  Creating transcript-level BED12 (a few minutes)..."
```

python3 - <<‘PYTHON_SCRIPT’ “${ANNOTATION_GTF}” “${TRANSCRIPT_BED}”
import sys
from collections import defaultdict

gtf_file = sys.argv[1]
bed_file = sys.argv[2]

transcripts = defaultdict(lambda: {
‘chr’: ‘’, ‘strand’: ‘’, ‘exons’: [],
‘gene_name’: ‘’, ‘start’: float(‘inf’), ‘end’: 0
})

print(”  Reading GTF…”, flush=True)
with open(gtf_file) as f:
for line in f:
if line.startswith(’#’):
continue
fields = line.strip().split(’\t’)
if len(fields) < 9 or fields[2] not in (‘transcript’, ‘exon’):
continue
chrom  = fields[0]
start  = int(fields[3]) - 1
end    = int(fields[4])
strand = fields[6]
attrs  = fields[8]
tid = gene_name = None
for attr in attrs.split(’;’):
attr = attr.strip()
if attr.startswith(‘transcript_id’):
tid = attr.split(’”’)[1]
elif attr.startswith(‘gene_name’):
gene_name = attr.split(’”’)[1]
if not tid:
continue
t = transcripts[tid]
t[‘chr’]    = chrom
t[‘strand’] = strand
t[‘start’]  = min(t[‘start’], start)
t[‘end’]    = max(t[‘end’],   end)
if gene_name and not t[‘gene_name’]:
t[‘gene_name’] = gene_name
if fields[2] == ‘exon’:
t[‘exons’].append((start, end))

print(”  Writing BED12…”, flush=True)
count = 0
with open(bed_file, ‘w’) as out:
for tid, d in sorted(transcripts.items()):
if not d[‘exons’]:
continue
exons = sorted(d[‘exons’])
s = d[‘start’]
name = d[‘gene_name’] or tid
out.write(
f”{d[‘chr’]}\t{s}\t{d[‘end’]}\t{name}\t1000\t{d[‘strand’]}\t”
f”{s}\t{d[‘end’]}\t0,0,0\t{len(exons)}\t”
f”{’,’.join(str(e-b) for b,e in exons)}\t”
f”{’,’.join(str(b-s) for b,e in exons)}\n”
)
count += 1
print(f”  Done. {count} transcripts written.”)
PYTHON_SCRIPT

```
NUM_TX=$(wc -l < "${TRANSCRIPT_BED}")
echo "  ✓ Transcript BED12: ${TRANSCRIPT_BED} (${NUM_TX} transcripts)"
```

fi

### ============================================================

### 完了サマリー

### ============================================================

cd ${BASE_DIR}
echo “”
echo “======================================================”
echo “✓ All steps completed successfully!”
echo “======================================================”
echo “”
echo “  [References]  ${REF_DIR}”
echo “  [Salmon index] ${SALMON_INDEX}”
echo “  [STAR index]   ${STAR_INDEX}”
echo “  [IGV BED]      ${IGV_DIR}”
echo “”
echo “  次のスクリプトでこれらのパスを設定してください:”
echo “    Salmon quant : SALMON_INDEX_DIR="${SALMON_INDEX}"”
echo “    STAR align   : STAR_INDEX_DIR="${STAR_INDEX}"”
echo “    tximport GTF : GTF="${REF_DIR}gencode.v49.primary_assembly.annotation.gtf"”
echo “”
echo “  IGVでの使い方:”
echo “    1. Genomes > Load Genome from File → GRCh38.primary_assembly.genome.fa”
echo “    2. File > Load from File → ${TRANSCRIPT_BED}”
echo “======================================================”