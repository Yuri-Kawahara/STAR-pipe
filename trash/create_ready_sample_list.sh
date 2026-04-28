#!/bin/bash

# トリミング済みFASTQが保存されているディレクトリ
TRIM_DIR="/qcresult/"
OUTPUT_LIST="star_ready_samples.txt"

echo "======================================================"
echo "トリミング済みディレクトリからSTAR用リストを作成します"
echo "ディレクトリ: ${TRIM_DIR}"
echo "======================================================"

if [ ! -d "${TRIM_DIR}" ]; then
    echo "エラー: ディレクトリが見つかりません - ${TRIM_DIR}"
    exit 1
fi

TEMP_LIST=$(mktemp)

# _trim_1.fq.gz を検索
find "${TRIM_DIR}" -maxdepth 1 -name "*_trim_1.fq.gz" | sort | while read file; do
    basename_file=$(basename "$file")
    # "_trim_1.fq.gz" を取り除いてサンプルIDを取得
    sample_id="${basename_file%_trim_1.fq.gz}"
    
    # 対応する R2 ファイルの確認
    file_r2="${TRIM_DIR}/${sample_id}_trim_2.fq.gz"
    
    if [ -f "$file_r2" ]; then
        echo "$sample_id" >> "$TEMP_LIST"
    else
        echo "警告: R2ファイルが見つかりません -> ${sample_id} (スキップします)"
    fi
done

if [ ! -s "$TEMP_LIST" ]; then
    echo "エラー: 有効なトリミング済みペアエンドファイルが見つかりません。"
    rm -f "$TEMP_LIST"
    exit 1
fi

sort -u "$TEMP_LIST" > "$OUTPUT_LIST"
rm -f "$TEMP_LIST"

NUM_SAMPLES=$(wc -l < "$OUTPUT_LIST" | awk '{print $1}')
echo "本番STAR用リスト作成完了: ${OUTPUT_LIST} (合計: ${NUM_SAMPLES} サンプル)"
