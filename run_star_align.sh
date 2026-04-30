#!/bin/bash
#$ -S /bin/bash
#$ -cwd
#$ -l s_vmem=8G
#$ -pe def_slot 16
#$ -N star_align_array
#$ -o array_logs/star_job.o$JOB_ID.$TASK_ID
#$ -e array_logs/star_job.e$JOB_ID.$TASK_ID

source ./config.sh

if [ -n "${SGE_TASK_ID}" ] && [ "${SGE_TASK_ID}" != "undefined" ]; then
    EXP_ID=$(sed -n "${SGE_TASK_ID}p" "${STAR_READY_LIST}")
    RUN_THREADS=$NSLOTS
else
    EXP_ID=$1
    RUN_THREADS=${THREADS}
fi

if [ -z "${EXP_ID}" ]; then exit 1; fi

module load star

# サンプルIDの先頭による切り替え（config.shのフラグを正規表現として使用）
if [[ "${EXP_ID}" =~ ${MOUSE_SAMP_KEY} ]]; then
    ACTIVE_INDEX=${STAR_INDEX_MM}
    ACTIVE_GTF=${GENCODE_GTF_MM}
elif [[ "${EXP_ID}" =~ ${HUMAN_SAMP_KEY} ]]; then
    ACTIVE_INDEX=${STAR_INDEX_HU}
    ACTIVE_GTF=${GENCODE_GTF_HU}
else
    echo "ERROR: Unknown species prefix in sample ID [${EXP_ID}]" >&2
    exit 1
fi

BAM_DIR="${STAR_OUTPUT_DIR}/bam"
LOG_DIR="${STAR_OUTPUT_DIR}/log_star"
TRIM_FASTQ_1="${TRIM_DIR}/${EXP_ID}_trim_1.fq.gz"
TRIM_FASTQ_2="${TRIM_DIR}/${EXP_ID}_trim_2.fq.gz"

STAR --runThreadN ${RUN_THREADS} \
     --genomeDir ${ACTIVE_INDEX} \
     --sjdbGTFfile ${ACTIVE_GTF} \
     --readFilesIn ${TRIM_FASTQ_1} ${TRIM_FASTQ_2} \
     --readFilesCommand zcat \
     --outFileNamePrefix ${BAM_DIR}/${EXP_ID}. \
     --twopassMode Basic \
    --outFilterMultimapNmax 20 \
    --alignSJDBoverhangMin 1 \
    --outFilterMismatchNmax 10 \
    --outFilterMultimapNmax 20 \
    --alignIntronMax 1000000 \
    --alignIntromMin 20 \ 
    --alignMatesGapMax 1000000 \
    --sjdbScore 2 \
    --limitBAMsortRAM 0 \
    --genomeLoad NoSharedMemory \
    --outFilterMatchNminOverLread 0.33 \
    --outFilterScoreMinOverLread 0.33 \
    --outSAMstrandField intronMotif \
    --outSAMtype BAM SortedByCoordinate \
    --quantMode GeneCounts TranscriptomeSAM \
    --outSAMunmapped Within \
    --outSAMattributes Standard \
    --quantMode GeneCounts \
    --chimSegmentMin 15 \
    --chimJunctionOverhangMin 15 \
    --chimOutType Junctions WithinBAM SoftClip \
    --chimMainSegmentMultNmax 1 \
    --chimOutJunctionFormat 1

mv ${BAM_DIR}/${EXP_ID}.Log.* ${LOG_DIR}/
mv ${BAM_DIR}/${EXP_ID}.SJ.out.tab ${LOG_DIR}/
