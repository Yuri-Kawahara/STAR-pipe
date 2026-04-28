#!/bin/bash

###############################################################################
# サンプルリスト作成スクリプト
# 
# 用途: FASTQファイルのディレクトリをスキャンして、ペアエンドRNA-seq
#       サンプルの一覧を作成し、ジョブアレイ用のテキストファイルを生成
#
# 使用方法:
#   bash create_sample_list.sh
#
# 出力:
#   zebra_samples.txt - 各サンプルIDが1行ずつ記載されたファイル
###############################################################################

### --- 設定項目 ---
# FASTQファイルが格納されているディレクトリ
FASTQ_DIR="/home/kawayuri/fastq/zebra/"

# 出力するサンプルリストファイル
OUTPUT_LIST="/home/kawayuri/fastq/zebra/zebra_samples.txt"

# FASTQファイルの命名パターン
# 例: sample1_1.fq.gz と sample1_2.fq.gz の場合
# パターン: *_1.fq.gz と *_2.fq.gz

### --- スクリプト本体 ---
echo "======================================================"
echo "Creating sample list from FASTQ directory"
echo "======================================================"
echo "FASTQ directory: ${FASTQ_DIR}"
echo "Output list: ${OUTPUT_LIST}"
echo ""

# ディレクトリの存在確認
if [ ! -d "${FASTQ_DIR}" ]; then
    echo "ERROR: FASTQ directory not found: ${FASTQ_DIR}"
    exit 1
fi

# 一時ファイル
TEMP_LIST=$(mktemp)

# _1.fq.gz ファイルを検索してサンプル名を抽出
echo "Scanning for FASTQ files..."
find "${FASTQ_DIR}" -name "*_1.fq.gz" | while read file; do
    # ベース名を取得（ディレクトリパスを除去）
    basename_file=$(basename "$file")
    
    # _1.fq.gz を削除してサンプルIDを取得
    sample_id="${basename_file%_1.fq.gz}"
    
    # 対応する _2.fq.gz ファイルの存在確認
    file_r2="${FASTQ_DIR}/${sample_id}_2.fq.gz"
    
    if [ -f "$file_r2" ]; then
        echo "$sample_id" >> "$TEMP_LIST"
        echo "  Found: ${sample_id}"
    else
        echo "  WARNING: Missing R2 for ${sample_id} (skipping)"
    fi
done

# 結果が空でないか確認
if [ ! -s "$TEMP_LIST" ]; then
    echo ""
    echo "ERROR: No valid paired-end FASTQ files found!"
    echo "Please check:"
    echo "  1. FASTQ directory path is correct"
    echo "  2. Files are named as: SAMPLEID_1.fq.gz and SAMPLEID_2.fq.gz"
    rm -f "$TEMP_LIST"
    exit 1
fi

# ソートしてユニークにし、最終ファイルに出力
sort -u "$TEMP_LIST" > "$OUTPUT_LIST"
rm -f "$TEMP_LIST"

# 結果サマリー
NUM_SAMPLES=$(wc -l < "$OUTPUT_LIST")

echo ""
echo "======================================================"
echo "Sample list created successfully!"
echo "======================================================"
echo "Total samples: ${NUM_SAMPLES}"
echo "Output file: ${OUTPUT_LIST}"
echo ""
echo "First 10 samples:"
head -10 "$OUTPUT_LIST"

if [ $NUM_SAMPLES -gt 10 ]; then
    echo "..."
    echo "(showing first 10 of ${NUM_SAMPLES} samples)"
fi

echo ""
echo "======================================================"
echo "Next steps:"
echo "======================================================"
echo "1. Review the sample list:"
echo "   cat ${OUTPUT_LIST}"
echo ""
echo "2. Submit the job array:"
echo "   qsub -t 1-${NUM_SAMPLES} fastq_pipe.sh"
echo ""
echo "   Or specify a range (e.g., first 10 samples):"
echo "   qsub -t 1-10 fastq_pipe.sh"
echo "======================================================"
