#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -l s_vmem=8G
#$ -pe def_slot 16
#$ -N SALMON_zebra_array
#$ -o array_logs/salmon_job.o$JOB_ID.$TASK_ID
#$ -e array_logs/salmon_job.e$JOB_ID.$TASK_ID

### --- 0. 準備：ログ用ディレクトリの作成 ---
mkdir -p array_logs

### --- 1. モジュールのロード ---
echo "Loading modules..."
module use /usr/local/package/modulefiles
module load salmon
module load fastqc
module load fastp

### --- 2. 変数の設定 ---
# スレッド数
THREADS=$NSLOTS

# サンプルIDリストファイル
SAMPLE_LIST="/home/kawayuri/fastq/zebra/zebra_samples.txt"

# salmon indexが保存されているディレクトリ
SALMON_INDEX_DIR="/home/kawayuri/gdc_reference/salmon/gencode.v36.salmon_index"

# 入力fastqディレクトリ
RAW_FASTQ_DIR="/home/kawayuri/fastq/zebra/"

# 出力ディレクトリ
OUTPUT_DIR="/home/kawayuri/SALMON_output/zebra/"

# 各種出力ディレクトリ
LOG_DIR="${OUTPUT_DIR}/log_SALMON"
QC_DIR="${OUTPUT_DIR}/qc_reports"
TRIM_DIR="${RAW_FASTQ_DIR}/trimmed/"

# 出力ディレクトリが存在しない場合に作成
mkdir -p ${BAM_DIR} ${LOG_DIR} ${QC_DIR} ${TRIM_DIR}

### --- 3. 担当サンプルの決定 ---
# ジョブアレイのタスクIDを基に、リストファイルから処理すべきサンプルIDを取得
EXP_ID=$(sed -n "${SGE_TASK_ID}p" ${SAMPLE_LIST})
printf "Processing Sample ID: %s\n" "${EXP_ID}"

# サンプルIDが取得できなかった場合は終了
if [ -z "${EXP_ID}" ]; then
    echo "Task ID ${SGE_TASK_ID} is out of the list range. Exiting."
    exit 0
fi

echo "======================================================"
echo "Job Task ID: ${SGE_TASK_ID}"
echo "Processing Sample ID: ${EXP_ID}"
echo "Using ${THREADS} threads."
echo "======================================================"

### --- 4. パイプライン実行 ---

# 各ファイルのパスを定義
RAW_FASTQ_1="${RAW_FASTQ_DIR}/${EXP_ID}_1.fq.gz"
RAW_FASTQ_2="${RAW_FASTQ_DIR}/${EXP_ID}_2.fq.gz"
TRIM_FASTQ_1="${TRIM_DIR}/${EXP_ID}_trim_1.fq.gz"
TRIM_FASTQ_2="${TRIM_DIR}/${EXP_ID}_trim_2.fq.gz"

# index check


### --- 4-1. 入力ファイルの確認 ---
echo "--- [Step 1/3] Checking input files for ${EXP_ID} ---"

if [ ! -f "${RAW_FASTQ_1}" ] || [ ! -f "${RAW_FASTQ_2}" ]; then
    echo "ERROR: FASTQ files not found for ${EXP_ID}"
    echo "  Expected: ${RAW_FASTQ_1}"
    echo "  Expected: ${RAW_FASTQ_2}"
    exit 1
fi

echo "Input files found:"
echo "  R1: ${RAW_FASTQ_1}"
echo "  R2: ${RAW_FASTQ_2}"

### --- 4-2. QC & トリミング ---
echo "--- [Step 2/3] Running FastQC and fastp for ${EXP_ID} ---"

# すでにトリム済みファイルがある場合はスキップ
if [ -f "${TRIM_FASTQ_1}" ] && [ -f "${TRIM_FASTQ_2}" ]; then
    echo "Trimmed FASTQ files already exist. Skipping fastp and FastQC."
else
    # FastQC（トリミング前）
    fastqc -t ${THREADS} --nogroup -o ${QC_DIR} ${RAW_FASTQ_1} ${RAW_FASTQ_2}

    # fastpによるトリミング
    fastp \
        -i ${RAW_FASTQ_1} \
        -I ${RAW_FASTQ_2} \
        -o ${TRIM_FASTQ_1} \
        -O ${TRIM_FASTQ_2} \
        -w ${THREADS} \
        --detect_adapter_for_pe \
        -j ${QC_DIR}/${EXP_ID}_fastp.json \
        -h ${QC_DIR}/${EXP_ID}_fastp.html

    if [ $? -ne 0 ]; then
        echo "ERROR: fastp failed for ${EXP_ID}. Aborting."
        exit 1
    fi
fi

### --- 4-3. salmon quant コマンド実行 ---
echo "--- Running Salmon quantification for ${EXP_ID} ---"
echo "Read 1: ${TRIM_FASTQ_1}"
echo "Read 2: ${TRIM_FASTQ_2}"
echo "Outputting to: ${OUTPUT_DIR}"
echo "------------------------------------------------------"

# salmon quant コマンド実行
salmon quant -i ${SALMON_INDEX_DIR} \
             -l A \
             -1 ${TRIM_FASTQ_1} \
             -2 ${TRIM_FASTQ_2} \
             -p ${THREADS} \
             --validateMappings \
             --gcBias \
             -o ${OUTPUT_DIR}/${EXP_ID}_quant 

# 実行が失敗した場合はエラーメッセージを出力して終了
if [ $? -ne 0 ]; then
    echo "ERROR: Salmon quantification failed for ${EXP_ID}."
    exit 1 # 異常終了
fi

echo "===== Successfully finished quantification for ${EXP_ID}. ====="
