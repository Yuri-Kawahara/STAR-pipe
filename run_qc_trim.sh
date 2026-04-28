#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -l s_vmem=8G
#$ -pe def_slot 16
#$ -N qc_trim_array
#$ -o array_logs/qc_job.o$JOB_ID.$TASK_ID
#$ -e array_logs/qc_job.e$JOB_ID.$TASK_ID

source ./config.sh

if [ -n "${SGE_TASK_ID}" ] && [ "${SGE_TASK_ID}" != "undefined" ]; then
    EXP_ID=$(sed -n "${SGE_TASK_ID}p" "${RAW_SAMPLE_LIST}")
    RUN_THREADS=$NSLOTS
else
    EXP_ID=$1
    RUN_THREADS=${THREADS}
fi

if [ -z "${EXP_ID}" ]; then exit 1; fi

module load fastqc
module load fastp

# IDが含まれるR1/R2ファイルをディレクトリ内から検索
RAW_FASTQ_1=$(ls ${RAW_FASTQ_DIR}/${EXP_ID}*R1*.gz | head -n 1)
RAW_FASTQ_2=$(ls ${RAW_FASTQ_DIR}/${EXP_ID}*R2*.gz | head -n 1)

TRIM_FASTQ_1="${TRIM_DIR}/${EXP_ID}_trim_1.fq.gz"
TRIM_FASTQ_2="${TRIM_DIR}/${EXP_ID}_trim_2.fq.gz"
QC_DIR="${STAR_OUTPUT_DIR}/qc_reports"

if [ ! -f "${TRIM_FASTQ_1}" ]; then
    fastqc -t ${RUN_THREADS} --nogroup -o ${QC_DIR} ${RAW_FASTQ_1} ${RAW_FASTQ_2}
    fastp -i ${RAW_FASTQ_1} -I ${RAW_FASTQ_2} -o ${TRIM_FASTQ_1} -O ${TRIM_FASTQ_2} \
          -w ${RUN_THREADS} --detect_adapter_for_pe \
          -j ${QC_DIR}/${EXP_ID}_fastp.json -h ${QC_DIR}/${EXP_ID}_fastp.html
fi
