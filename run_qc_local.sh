#!/bin/bash

# =====================================================
# run_qc_trim_local.sh  ― ローカルMac用 QC & trim 一括実行
# 
# 元の run_qc_trim.sh からの主な変更点:
# - SGEヘッダー (#$ -…) を除去
# - SGE_TASK_ID / NSLOTS 分岐を除去
# - module load を除去（fastqc / fastp は PATH 直入り想定）
# - サンプルリストをループで順次処理
# - set -euo pipefail & エラーチェックを追加
# - config.sh を source (修正済み)
# =====================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# —————————————————––
# ツール確認
# —————————————————––
for tool in fastqc fastp; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: ${tool} が見つかりません。brew install ${tool} などで導入してください。"
        exit 1
    fi
done

# —————————————————––
# サンプルリスト確認
# —————————————————––
if [ ! -f "${RAW_SAMPLE_LIST}" ]; then
    echo "ERROR: サンプルリストが見つかりません: ${RAW_SAMPLE_LIST}"
    echo "  先に create_sample_qclist_20260428.sh (またはそのローカル版) を実行してください。"
    exit 1
fi

TOTAL=$(wc -l < "${RAW_SAMPLE_LIST}" | tr -d ' ')
echo "======================================================"
echo " QC & Trim  ―  ローカル順次実行"
echo " サンプル数 : ${TOTAL}"
echo " FASTQ DIR  : ${RAW_FASTQ_DIR}"
echo " TRIM DIR   : ${TRIM_DIR}"
echo " QC DIR     : ${STAR_OUTPUT_DIR}/qc_reports"
echo " THREADS    : ${THREADS}"
echo "======================================================"

COUNT=0
SKIP=0
FAIL=0

while IFS= read -r EXP_ID; do
    # 空行・コメント行スキップ
    [[ -z "${EXP_ID}" || "${EXP_ID}" =~ ^# ]] && continue

    COUNT=$((COUNT + 1))
    echo ""
    echo "[${COUNT}/${TOTAL}] ${EXP_ID}"

    # --- 出力ファイルパス ---
    TRIM_FASTQ_1="${TRIM_DIR}/${EXP_ID}_trim_1.fq.gz"
    TRIM_FASTQ_2="${TRIM_DIR}/${EXP_ID}_trim_2.fq.gz"
    QC_DIR="${STAR_OUTPUT_DIR}/qc_reports"

    # --- スキップ判定（元スクリプトと同じ条件）---
    if [ -f "${TRIM_FASTQ_1}" ]; then
        echo "  ✓ Already trimmed (skip): ${TRIM_FASTQ_1}"
        SKIP=$((SKIP + 1))
        continue
    fi

    # --- 入力FASTQの検索 ---
    RAW_FASTQ_1=$(ls "${RAW_FASTQ_DIR}/${EXP_ID}"*R1*.gz 2>/dev/null | head -n 1 || true)
    RAW_FASTQ_2=$(ls "${RAW_FASTQ_DIR}/${EXP_ID}"*R2*.gz 2>/dev/null | head -n 1 || true)

    if [ -z "${RAW_FASTQ_1}" ] || [ -z "${RAW_FASTQ_2}" ]; then
        echo "  WARNING: R1/R2 FASTQが見つかりません。スキップします。(ID: ${EXP_ID})"
        FAIL=$((FAIL + 1))
        continue
    fi

    echo "  R1: $(basename "${RAW_FASTQ_1}")"
    echo "  R2: $(basename "${RAW_FASTQ_2}")"

    # --- FastQC（トリム前）---
    echo "  Running FastQC..."
    fastqc -t "${THREADS}" --nogroup -o "${QC_DIR}" \
        "${RAW_FASTQ_1}" "${RAW_FASTQ_2}"

    # --- fastp トリミング ---
    echo "  Running fastp..."
    fastp \
        -i  "${RAW_FASTQ_1}" \
        -I  "${RAW_FASTQ_2}" \
        -o  "${TRIM_FASTQ_1}" \
        -O  "${TRIM_FASTQ_2}" \
        -w  "${THREADS}" \
        --detect_adapter_for_pe \
        -j  "${QC_DIR}/${EXP_ID}_fastp.json" \
        -h  "${QC_DIR}/${EXP_ID}_fastp.html"

    echo "  ✓ Done: ${EXP_ID}"

done < "${RAW_SAMPLE_LIST}"

# —————————————————––
# サマリー
# —————————————————––
echo ""
echo "======================================================"
echo "  完了サマリー"
echo "  処理済み : $((COUNT - SKIP - FAIL))"
echo "  スキップ : ${SKIP}  (既存trimファイルあり)"
echo "  警告     : ${FAIL}  (FASTQが見つからなかったサンプル)"
echo "======================================================"
