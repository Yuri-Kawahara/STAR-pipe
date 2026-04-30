#!/bin/bash

# =====================================================

# run_star_align_local.sh  ― ローカルMac用 STAR アライメント

# 

# 元の run_star_align.sh からの変更点:

# - SGEヘッダー (#$ -…) を除去

# - SGE_TASK_ID / NSLOTS 分岐を除去

# - module load star を除去（STAR は PATH 直入り想定）

# - STAR_READY_LIST をループで順次処理

# - set -euo pipefail & エラーチェックを追加

# - config_local.sh を source

# =====================================================

set -euo pipefail

SCRIPT_DIR=”$(cd “$(dirname “${BASH_SOURCE[0]}”)” && pwd)”
source “${SCRIPT_DIR}/config.sh”

# —————————————————––

# ツール確認

# —————————————————––

if ! command -v STAR &>/dev/null; then
echo “ERROR: STAR が見つかりません。インストールしてください。”
echo “  Mac: brew install star”
exit 1
fi

# —————————————————––

# サンプルリスト確認

# —————————————————––

if [ ! -f “${STAR_READY_LIST}” ]; then
echo “ERROR: サンプルリストが見つかりません: ${STAR_READY_LIST}”
echo “  run_qc_trim_local.sh を先に実行してください。”
exit 1
fi

TOTAL=$(wc -l < “${STAR_READY_LIST}” | tr -d ’ ’)
BAM_DIR=”${STAR_OUTPUT_DIR}/bam”
LOG_DIR=”${STAR_OUTPUT_DIR}/log_star”

echo “======================================================”
echo “ STAR Alignment  ―  ローカル順次実行”
echo “ サンプル数 : ${TOTAL}”
echo “ TRIM DIR   : ${TRIM_DIR}”
echo “ BAM DIR    : ${BAM_DIR}”
echo “ THREADS    : ${THREADS}”
echo “======================================================”

COUNT=0
SKIP=0
FAIL=0

while IFS= read -r EXP_ID; do
[[ -z “${EXP_ID}” || “${EXP_ID}” =~ ^# ]] && continue

```
COUNT=$((COUNT + 1))
echo ""
echo "[${COUNT}/${TOTAL}] ${EXP_ID}"

# --- trimファイル確認 ---
TRIM_FASTQ_1="${TRIM_DIR}/${EXP_ID}_trim_1.fq.gz"
TRIM_FASTQ_2="${TRIM_DIR}/${EXP_ID}_trim_2.fq.gz"

if [ ! -f "${TRIM_FASTQ_1}" ] || [ ! -f "${TRIM_FASTQ_2}" ]; then
    echo "  WARNING: trimファイルが見つかりません。スキップします。"
    echo "    ${TRIM_FASTQ_1}"
    FAIL=$((FAIL + 1))
    continue
fi

# --- スキップ判定（BAMが既存なら飛ばす）---
if [ -f "${BAM_DIR}/${EXP_ID}.Aligned.sortedByCoord.out.bam" ]; then
    echo "  ✓ Already aligned (skip)"
    SKIP=$((SKIP + 1))
    continue
fi

# --- マウス / ヒト の判定 ---
if [[ "${EXP_ID}" =~ ${MOUSE_SAMP_KEY} ]]; then
    ACTIVE_INDEX="${STAR_INDEX_MM}"
    ACTIVE_GTF="${GENCODE_GTF_MM}"
    echo "  Species: Mouse"
elif [[ "${EXP_ID}" =~ ${HUMAN_SAMP_KEY} ]]; then
    ACTIVE_INDEX="${STAR_INDEX_HU}"
    ACTIVE_GTF="${GENCODE_GTF_HU}"
    echo "  Species: Human"
else
    echo "  ERROR: サンプルIDの先頭が mm / Hu のどちらにもマッチしません: ${EXP_ID}"
    echo "  config_local.sh の MOUSE_SAMP_KEY / HUMAN_SAMP_KEY を確認してください。"
    FAIL=$((FAIL + 1))
    continue
fi

# --- インデックス・GTF存在確認 ---
if [ ! -d "${ACTIVE_INDEX}" ]; then
    echo "  ERROR: STARインデックスが見つかりません: ${ACTIVE_INDEX}"
    FAIL=$((FAIL + 1))
    continue
fi
if [ ! -f "${ACTIVE_GTF}" ]; then
    echo "  ERROR: GTFが見つかりません: ${ACTIVE_GTF}"
    FAIL=$((FAIL + 1))
    continue
fi

# --- STAR アライメント ---
echo "  Running STAR..."
STAR --runThreadN "${THREADS}" \
    --genomeDir "${ACTIVE_INDEX}" \
    --sjdbGTFfile "${ACTIVE_GTF}" \
    --readFilesIn "${TRIM_FASTQ_1}" "${TRIM_FASTQ_2}" \
    --readFilesCommand zcat \
    --outFileNamePrefix "${BAM_DIR}/${EXP_ID}." \
    --twopassMode Basic \
    --outFilterMultimapNmax 20 \
    --alignSJDBoverhangMin 1 \
    --outFilterMismatchNmax 10 \
    --alignIntronMax 300000 \
    --alignMatesGapMax 300000 \
    --sjdbScore 2 \
    --genomeLoad NoSharedMemory \
    --outFilterMatchNminOverLread 0.33 \
    --outFilterScoreMinOverLread 0.33 \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMunmapped Within \
    --outSAMattributes Standard \
    --quantMode GeneCounts \
    --chimSegmentMin 15 \
    --chimJunctionOverhangMin 15 \
    --chimOutType Junctions WithinBAM SoftClip \
    --chimMainSegmentMultNmax 1 \
    --chimOutJunctionFormat 1

if [ $? -eq 0 ]; then
    # ログ・SJファイルをlog_starに移動
    mv "${BAM_DIR}/${EXP_ID}".Log.* "${LOG_DIR}/"
    mv "${BAM_DIR}/${EXP_ID}.SJ.out.tab" "${LOG_DIR}/"
    echo "  ✓ Done: ${EXP_ID}"
else
    echo "  ERROR: STAR failed for ${EXP_ID}"
    FAIL=$((FAIL + 1))
fi
```

done < “${STAR_READY_LIST}”

# —————————————————––

# サマリー

# —————————————————––

echo “”
echo “======================================================”
echo “  完了サマリー”
echo “  処理済み : $((COUNT - SKIP - FAIL))”
echo “  スキップ : ${SKIP}  (既存BAMあり)”
echo “  警告     : ${FAIL}  (trimファイル未発見 / 種族不明 / ツールエラー)”
echo “======================================================”