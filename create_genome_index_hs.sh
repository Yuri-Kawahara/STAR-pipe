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
# 参照: GENCODE v49 / GRCh38
###############################################################################

BASE_DIR="/home/kawayuri"
REF_DIR="${BASE_DIR}/Reference/human/"
SALMON_INDEX="${BASE_DIR}/gdc_reference/salmon/gencode.v49.human_salmon_index/"
STAR_INDEX="${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index/"
IGV_DIR="${REF_DIR}igv/"
THREADS=16
OVERHANG=149

USE_CUSTOM_FUSION=false
CUSTOM_FUSION_FA="${REF_DIR}custom_fusion_genes.fa"
EXCLUDE_WILDTYPE_GENES=""

set -euo pipefail

echo "Loading modules..."
module use /usr/local/package/modulefiles
module load star
module load salmon

BASE_DIR=$(pwd)
mkdir -p logs

echo "======================================================"
echo " Human Reference Build"
echo " GENCODE v49 / GRCh38"
echo " Custom fusion: ${USE_CUSTOM_FUSION}"
echo "======================================================"

### Step 1: リファレンスファイルのダウンロード
echo ""
echo "Step 1: Downloading reference files (GENCODE v49)..."
mkdir -p ${REF_DIR} && cd ${REF_DIR}

download_if_missing() {
    local url=$1
    local filename=$(basename ${url%.gz})
    if [ -f "${filename}" ]; then
        echo "  ✓ Already exists (skip): ${filename}"
    else
        echo "  Downloading: $(basename $url)"
        wget -q --show-progress "$url"
        gunzip "$(basename $url)"
        echo "  ✓ Done: ${filename}"
    fi
}

download_if_missing "[https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/gencode.v49.transcripts.fa.gz](https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/gencode.v49.transcripts.fa.gz)"
download_if_missing "[https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/GRCh38.primary_assembly.genome.fa.gz](https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/GRCh38.primary_assembly.genome.fa.gz)"
download_if_missing "[https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/gencode.v49.primary_assembly.annotation.gtf.gz](https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_49/gencode.v49.primary_assembly.annotation.gtf.gz)"

echo "✓ All reference files ready."

### Step 1.5: 融合遺伝子GTFの作成
if [ "${USE_CUSTOM_FUSION}" = "true" ]; then
    echo ""
    echo "Step 1.5: Creating fusion gene GTF..."

    if [ ! -f "${CUSTOM_FUSION_FA}" ]; then
        echo "ERROR: CUSTOM_FUSION_FA not found: ${CUSTOM_FUSION_FA}"
        exit 1
    fi

    FUSION_GTF="${REF_DIR}fusion_genes.gtf"
    BASE_GTF="${REF_DIR}gencode.v49.primary_assembly.annotation.gtf"

    echo "  Custom fusion FASTA: ${CUSTOM_FUSION_FA}"
    grep '^>' "${CUSTOM_FUSION_FA}" | sed 's/>/    · /'

    echo "  Generating fusion_genes.gtf from FASTA..."
    awk '
    BEGIN { gene_name = ""; sequence = "" }
    /^>/ {
        if (gene_name != "" && sequence != "") {
            seq_len = length(sequence);
            printf "%s\tcustom\tgene\t1\t%d\t.\t+\t.\tgene_id \"%s\"; gene_name \"%s\"; gene_biotype \"fusion\";\n", gene_name, seq_len, gene_name, gene_name;
            printf "%s\tcustom\ttranscript\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; gene_name \"%s\"; gene_biotype \"fusion\";\n", gene_name, seq_len, gene_name, gene_name, gene_name;
            printf "%s\tcustom\texon\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; exon_number \"1\"; gene_name \"%s\"; gene_biotype \"fusion\";\n", gene_name, seq_len, gene_name, gene_name, gene_name;
        }
        gene_name = $1; sub(/^>/, "", gene_name);
        sequence = "";
    }
    !/^>/ { gsub(/[[:space:]]/, "", $0); sequence = sequence $0 }
    END {
        if (gene_name != "" && sequence != "") {
            seq_len = length(sequence);
            printf "%s\tcustom\tgene\t1\t%d\t.\t+\t.\tgene_id \"%s\"; gene_name \"%s\"; gene_biotype \"fusion\";\n", gene_name, seq_len, gene_name, gene_name;
            printf "%s\tcustom\ttranscript\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; gene_name \"%s\"; gene_biotype \"fusion\";\n", gene_name, seq_len, gene_name, gene_name, gene_name;
            printf "%s\tcustom\texon\t1\t%d\t.\t+\t.\tgene_id \"%s\"; transcript_id \"%s_transcript\"; exon_number \"1\"; gene_name \"%s\"; gene_biotype \"fusion\";\n", gene_name, seq_len, gene_name, gene_name, gene_name;
        }
    }
    ' "${CUSTOM_FUSION_FA}" > "${FUSION_GTF}"

    if [ -n "${EXCLUDE_WILDTYPE_GENES}" ]; then
        EXCLUDE_PATTERN=$(echo "${EXCLUDE_WILDTYPE_GENES}" | tr ' ' '|')
        FILTERED_GTF="${REF_DIR}filtered_human.gtf"
        grep -v -E "gene_name \"(${EXCLUDE_PATTERN})\"" "${BASE_GTF}" > "${FILTERED_GTF}"
        MERGE_BASE="${FILTERED_GTF}"
    else
        MERGE_BASE="${BASE_GTF}"
    fi

    HYBRID_GTF="${REF_DIR}hybrid_annotation.gtf"
    cat "${MERGE_BASE}" "${FUSION_GTF}" > "${HYBRID_GTF}"
    echo "  ✓ Hybrid GTF created: ${HYBRID_GTF}"
else
    echo ""
    echo "Step 1.5: Skipped (USE_CUSTOM_FUSION=false)"
fi

### Step 2: Salmon decoy-aware インデックスの構築 (コメントアウト維持)
# echo ""
# echo "Step 2: Building Salmon decoy-aware index..."
# if [ -d "${SALMON_INDEX}" ] && [ -f "${SALMON_INDEX}/info.json" ]; then
#     echo "  ✓ Salmon index already exists. Skipping."
# else
#     mkdir -p ${SALMON_INDEX}
#     echo "  Creating decoy list..."
#     grep '^>' GRCh38.primary_assembly.genome.fa | cut -d ' ' -f 1 | sed 's/>//' > decoys.txt
#     if [ "${USE_CUSTOM_FUSION}" = "true" ]; then
#         cat gencode.v49.transcripts.fa "${CUSTOM_FUSION_FA}" GRCh38.primary_assembly.genome.fa > gentrome_human.fa
#     else
#         cat gencode.v49.transcripts.fa GRCh38.primary_assembly.genome.fa > gentrome_human.fa
#     fi
#     salmon index -t gentrome_human.fa -d decoys.txt -i ${SALMON_INDEX} -p ${THREADS}
# fi

### Step 3: STAR ゲノムインデックスの構築
echo ""
echo "Step 3: Building STAR genome index..."

if [ -d "${STAR_INDEX}" ] && [ -f "${STAR_INDEX}/SAindex" ]; then
    echo "  ✓ STAR index already exists. Skipping."
else
    mkdir -p ${STAR_INDEX}

    if [ "${USE_CUSTOM_FUSION}" = "true" ]; then
        cat GRCh38.primary_assembly.genome.fa "${CUSTOM_FUSION_FA}" > hybrid_genome.fa
        GENOME_FA="${REF_DIR}hybrid_genome.fa"
        ANNOTATION_GTF="${REF_DIR}hybrid_annotation.gtf"
    else
        GENOME_FA="${REF_DIR}GRCh38.primary_assembly.genome.fa"
        ANNOTATION_GTF="${REF_DIR}gencode.v49.primary_assembly.annotation.gtf"
    fi

    STAR --runMode genomeGenerate \
         --runThreadN ${THREADS} \
         --genomeDir ${STAR_INDEX} \
         --genomeFastaFiles "${GENOME_FA}" \
         --sjdbGTFfile "${ANNOTATION_GTF}" \
         --sjdbOverhang ${OVERHANG} \
         --genomeSAindexNbases 14

    echo "✓ STAR index created: ${STAR_INDEX}"
fi

### Step 4: IGV用 BEDファイルの作成
echo ""
echo "Step 4: Creating IGV BED files..."
mkdir -p ${IGV_DIR}

ANNOTATION_GTF="${REF_DIR}gencode.v49.primary_assembly.annotation.gtf"
GENE_BED="${IGV_DIR}human_genes.bed"
TRANSCRIPT_BED="${IGV_DIR}human_transcripts.bed"

if [ -f "${TRANSCRIPT_BED}" ]; then
    echo "  ✓ IGV BED files already exist. Skipping."
else
    echo "  Creating gene-level BED6..."
    awk -F'\t' 'BEGIN {OFS="\t"}
    /^#/ { next }
    $3 == "gene" {
        match($9, /gene_id "([^"]+)"/, gid);
        match($9, /gene_name "([^"]+)"/, gname);
        name = (gname[1] != "") ? gname[1] : gid[1];
        print $1, $4-1, $5, name, "1000", $7;
    }' "${ANNOTATION_GTF}" | sort -k1,1 -k2,2n > "${GENE_BED}"

    echo "  Creating transcript-level BED12 (a few minutes)..."
    python3 - <<'PYTHON_SCRIPT' "${ANNOTATION_GTF}" "${TRANSCRIPT_BED}"
import sys
from collections import defaultdict

gtf_file = sys.argv[1]
bed_file = sys.argv[2]

transcripts = defaultdict(lambda: {
    'chr': '', 'strand': '', 'exons': [],
    'gene_name': '', 'start': float('inf'), 'end': 0
})

with open(gtf_file) as f:
    for line in f:
        if line.startswith('#'):
            continue
        fields = line.strip().split('\t')
        if len(fields) < 9 or fields[2] not in ('transcript', 'exon'):
            continue
        chrom  = fields[0]
        start  = int(fields[3]) - 1
        end    = int(fields[4])
        strand = fields[6]
        attrs  = fields[8]
        tid = gene_name = None
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
        if fields[2] == 'exon':
            t['exons'].append((start, end))

with open(bed_file, 'w') as out:
    for tid, d in sorted(transcripts.items()):
        if not d['exons']:
            continue
        exons = sorted(d['exons'])
        s = d['start']
        name = d['gene_name'] or tid
        out.write(
            f"{d['chr']}\t{s}\t{d['end']}\t{name}\t1000\t{d['strand']}\t"
            f"{s}\t{d['end']}\t0,0,0\t{len(exons)}\t"
            f"{','.join(str(e-b) for b,e in exons)}\t"
            f"{','.join(str(b-s) for b,e in exons)}\n"
        )
PYTHON_SCRIPT
fi

echo "======================================================"
echo "✓ All steps completed successfully!"
echo "======================================================"
