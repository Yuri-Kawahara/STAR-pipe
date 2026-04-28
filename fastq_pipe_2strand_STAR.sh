#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -l s_vmem=8G
#$ -pe def_slot 16
#$ -N star_zebra_array
#$ -o array_logs/star_job.o$JOB_ID.$TASK_ID
#$ -e array_logs/star_job.e$JOB_ID.$TASK_ID

### --- 0. 準備：ログ用ディレクトリの作成 ---
mkdir -p array_logs

### --- 1. モジュールのロード ---
echo "Loading modules..."
module use /usr/local/package/modulefiles
module load star
module load fastqc
module load fastp

### --- 2. 変数の設定 ---
# スレッド数
THREADS=$NSLOTS

# サンプルIDリストファイル
SAMPLE_LIST="/home/kawayuri/fastq/zebra/zebra_samples.txt"

# STARインデックスのディレクトリ（ハイブリッドゲノム: ゼブラフィッシュ + ヒト）
# create_hybrid_genome_index.sh で作成したインデックスを使用
STAR_INDEX_DIR="/home/kawayuri/gdc_reference/zebra_index"

# 入力fastqディレクトリ
RAW_FASTQ_DIR="/home/kawayuri/fastq/zebra/"

# 出力ディレクトリ
OUTPUT_DIR="/home/kawayuri/STAR_output/zebra/"

# 各種出力ディレクトリ
BAM_DIR="${OUTPUT_DIR}/bam"
LOG_DIR="${OUTPUT_DIR}/log_star"
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

### --- 4-3. STAR アライメント ---
echo "--- [Step 3/3] Running STAR alignment for ${EXP_ID} ---"
# STARの実行 (2-pass & quantification)
STAR \
    --runThreadN ${THREADS} \
    --genomeDir ${STAR_INDEX_DIR} \
    --readFilesIn ${TRIM_FASTQ_1} ${TRIM_FASTQ_2} \
    --readFilesCommand zcat \
    --outFileNamePrefix ${BAM_DIR}/${EXP_ID}. \
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

# STARが失敗した場合は、エラーを記録して終了
if [ $? -ne 0 ]; then
    echo "ERROR: STAR alignment failed for ${EXP_ID}. Aborting."
    exit 1
fi
     
### --- 4-4. 後処理 ---
echo "--- [Step 4/4] Finalizing and cleaning up for ${EXP_ID} ---"
# STARが生成したログファイルを専用ディレクトリに移動
mv ${BAM_DIR}/${EXP_ID}.Log.* ${LOG_DIR}/
mv ${BAM_DIR}/${EXP_ID}.SJ.out.tab ${LOG_DIR}/

echo "===== Successfully finished processing ${EXP_ID} ====="
