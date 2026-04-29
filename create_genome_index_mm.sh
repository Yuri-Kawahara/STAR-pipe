#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -l s_vmem=8G
#$ -pe def_slot 16
#$ -N star_index_mm
#$ -o logs/star_index.o$JOB_ID
#$ -e logs/star_index.e$JOB_ID

### --- 1. モジュールのロード ---
echo "Loading modules..."
module use /usr/local/package/modulefiles
module load star
module load salmon

BASE_DIR=$(pwd)

### --- 0. 準備：ログ用ディレクトリの作成 ---
mkdir -p logs
mkdir -p ~/Reference/mouse && cd ~/Reference/mouse

download_if_missing() {
    local url="$1"
    # URLからファイル名を取得し、.gzを除いた名前をターゲットとする
    local gzipped_file=$(basename "$url")
    local filename="${gzipped_file%.gz}"

    if [ -f "${filename}" ]; then
        echo "  ✓ Already exists (skip): ${filename}"
    else
        echo "  Downloading: ${gzipped_file} from EBI..."
        
        # --timeout: 接続待ち時間を30秒に制限
        # --tries: 失敗しても10回リトライ
        # --continue: 中断された場合に途中から再開
        if wget --timeout=30 --tries=10 --continue --show-progress "$url"; then
            echo "  Extracting: ${gzipped_file}"
            # -f で上書き確認をスキップ
            gunzip -f "${gzipped_file}"
            echo "  ✓ Done: ${filename}"
        else
            echo "  Error: Failed to download ${url} after multiple attempts."
            return 1
        fi
    fi
}


download_if_missing "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M38/gencode.vM38.transcripts.fa.gz"
download_if_missing "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M38/GRCm39.primary_assembly.genome.fa.gz"
download_if_missing "https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse/release_M38/gencode.vM38.primary_assembly.annotation.gtf.gz"

# # ゲノムのchromo名だけ抜き出す（decoyファイル）
# grep '^>' GRCm39.primary_assembly.genome.fa \
#     | cut -d ' ' -f 1 \
#     | sed 's/>//' \
#     > decoys.txt

# head -3 decoys.txt  # chr1, chr2... となっていればOK

# # トランスクリプトーム + ゲノムを結合（この順番が必須）
# cat gencode.vM38.transcripts.fa \
#     GRCm39.primary_assembly.genome.fa \
#     > gentrome_mouse.fa

# # Salmonインデックス構築
# salmon index \
#     -t gentrome_mouse.fa \
#     -d decoys.txt \
#     -i gencode.vM38.M_salmon_index \
#     -p 16


cd ${BASE_DIR}

###############################################################################
# ゲノムインデックス作成スクリプト（マウスゲノム版）
###############################################################################

### --- パス設定 ---
REF_DIR=${BASE_DIR}/Reference/mouse/

MOUSE_GENOME="${REF_DIR}GRCm39.primary_assembly.genome.fa"
MOUSE_GTF="${REF_DIR}gencode.vM38.primary_assembly.annotation.gtf"

STAR_INDEX=${BASE_DIR}/gdc_reference/mm39_star_index/
THREADS=16

mkdir -p ${STAR_INDEX}
mkdir -p logs

### --- ステップ1: 入力ファイル確認 ---
echo "Step 1: Checking input files..."

if [ ! -f "${MOUSE_GENOME}" ]; then
    echo "ERROR: Mouse genome not found: ${MOUSE_GENOME}"; exit 1
fi
if [ ! -f "${MOUSE_GTF}" ]; then
    echo "ERROR: Mouse GTF not found: ${MOUSE_GTF}"; exit 1
fi

echo "✓ Mouse genome : ${MOUSE_GENOME}"
echo "✓ Mouse GTF    : ${MOUSE_GTF} (GRCm39 / GENCODE M38)"

### --- ステップ2: STARインデックス生成 ---
echo "Step 2: Generating STAR genome index (this takes ~30 min)..."

# 既存インデックスチェック
if [ -d "${STAR_INDEX}" ] && [ -f "${STAR_INDEX}/SAindex" ]; then
    echo "WARNING: Index already exists at ${STAR_INDEX}. Skipping."
    exit 0
fi

STAR --runMode genomeGenerate \
     --runThreadN ${THREADS} \
     --genomeDir ${STAR_INDEX} \
     --genomeFastaFiles "${MOUSE_GENOME}" \
     --sjdbGTFfile "${MOUSE_GTF}" \
     --sjdbOverhang 149 \
     --genomeSAindexNbases 14

if [ $? -eq 0 ]; then
    echo "✓ STAR index created: ${STAR_INDEX}"
else
    echo "ERROR: STAR index generation failed."; exit 1
fi
