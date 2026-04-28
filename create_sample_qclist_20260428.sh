#!/bin/bash
source ./config.sh

echo "======================================================"
echo "Creating sample list (Flexible R1/R2 Middle Pattern)"
echo "======================================================"

if [ ! -d "${RAW_FASTQ_DIR}" ]; then
    echo "ERROR: FASTQ directory not found: ${RAW_FASTQ_DIR}"
    exit 1
fi

TEMP_LIST=$(mktemp)

# "R1" を含むファイルを検索
find "${RAW_FASTQ_DIR}" -maxdepth 1 -type f -name "*R1*" | sort | while read f1; do
    basename_f1=$(basename "$f1")
    
    # R2ファイルの存在確認（ファイル名の中の R1 を R2 に置換）
    basename_f2="${basename_f1/R1/R2}"
    f2="${RAW_FASTQ_DIR}/${basename_f2}"
    
    if [ -f "$f2" ]; then
        # サンプルIDとして、ファイル名から R1(および前後の区切り文字) を抜いたものを使用
        # 例: SampleA_R1_L001.fq.gz -> SampleA_L001
        sample_id=$(echo "$basename_f1" | sed -E 's/[._-]R1[._-]/_/; s/[._-]R1//; s/R1//' | sed -E 's/\.(fastq|fq)\.gz$//')
        echo "$sample_id" >> "$TEMP_LIST"
    fi
done

sort -u "$TEMP_LIST" > "${RAW_SAMPLE_LIST}"
rm -f "$TEMP_LIST"

echo "Sample list created: ${RAW_SAMPLE_LIST}"
