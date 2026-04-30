#!/bin/bash

# =====================================================

# create_sample_qclist_local.sh  ― ローカルMac用

# 

# 元の create_sample_qclist_20260428.sh からの変更点:

# - config_local.sh を source

# - サンプルリストの形式を変更:

# 旧: EXP_ID（R1を除去した文字列） → ファイル検索が壊れやすい

# 新: EXP_ID<TAB>R1パス<TAB>R2パス → 完全に一意で検索不要

# =====================================================

set -euo pipefail

SCRIPT_DIR=”$(cd “$(dirname “${BASH_SOURCE[0]}”)” && pwd)”
source “${SCRIPT_DIR}/config.sh”

echo “======================================================”
echo “ Creating sample list”
echo “ FASTQ DIR: ${RAW_FASTQ_DIR}”
echo “======================================================”

if [ ! -d “${RAW_FASTQ_DIR}” ]; then
echo “ERROR: FASTQ directory not found: ${RAW_FASTQ_DIR}”
exit 1
fi

TEMP_LIST=$(mktemp)

find “${RAW_FASTQ_DIR}” -maxdepth 1 -type f -name “*R1*.gz” | sort | while read -r f1; do
basename_f1=$(basename “$f1”)

# R1→R2に置換してペアファイルを特定
basename_f2="${basename_f1/R1/R2}"
f2="${RAW_FASTQ_DIR}/${basename_f2}"

if [ ! -f "$f2" ]; then
    echo "  WARNING: R2ペアが見つかりません: ${basename_f1} → スキップ"
    continue
fi

# サンプルID: R1ファイル名から拡張子と _R1/_R1_ を除去
# パターン例:
#   SampleA_R1_L001.fq.gz   → SampleA_L001
#   SampleA_L001_R1.fq.gz   → SampleA_L001
#   SampleA_R1.fq.gz        → SampleA
#   SampleA_001_R1_001.fq.gz → SampleA_001_001
sample_id=$(echo "$basename_f1" \
    | sed -E 's/\.(fastq|fq)\.gz$//' \
    | sed -E 's/[._-]R1[._-]/_/g' \
    | sed -E 's/[._-]R1$//' \
    | sed -E 's/^R1[._-]//' \
    | sed -E 's/_+$//; s/^_+//')

# TSV形式で記録: EXP_ID <TAB> R1フルパス <TAB> R2フルパス
printf "%s\t%s\t%s\n" "${sample_id}" "${f1}" "${f2}" >> "$TEMP_LIST"

done

sort -u “$TEMP_LIST” > “${RAW_SAMPLE_LIST}”
rm -f “$TEMP_LIST”

COUNT=$(wc -l < “${RAW_SAMPLE_LIST}” | tr -d ’ ’)
echo “”
echo “✓ サンプルリスト作成完了: ${RAW_SAMPLE_LIST} (${COUNT} サンプル)”
echo “”
echo “— 内容プレビュー —”
column -t “${RAW_SAMPLE_LIST}”