#!/bin/bash

# mouse sample flag
MOUSE_SAMP_KEY="^ms"

# human sample flag
HUMAN_SAMP_KEY="^Hu"

# --- プロジェクト基本ディレクトリ ---
BASE_DIR="/home/kawayuri"

# --- 入力データパス ---
RAW_FASTQ_DIR="${BASE_DIR}/fastq/zebra"
TRIM_DIR="${RAW_FASTQ_DIR}/trimmed"

# --- リファレンス・インデックスパス ---
STAR_INDEX_MM="${BASE_DIR}/gdc_reference/mm39_star_index"
STAR_INDEX_HU="${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index"

GENCODE_GTF_MM="${BASE_DIR}/Reference/mouse/gencode.vM38.primary_assembly.annotation.gtf"
GENCODE_GTF_HU="${BASE_DIR}/Reference/human/gencode.v49.primary_assembly.annotation.gtf"

# --- 出力先ディレクトリ ---
STAR_OUTPUT_DIR="${BASE_DIR}/STAR_output/mouse"

# --- 実行パラメータ ---
THREADS=16

# --- リストファイル名 ---
RAW_SAMPLE_LIST="samples_202604.txt"
STAR_READY_LIST="star_ready_samples.txt"

# --- ディレクトリの自動作成 ---
mkdir -p "${TRIM_DIR}"
mkdir -p "${STAR_OUTPUT_DIR}/bam"
mkdir -p "${STAR_OUTPUT_DIR}/log_star"
mkdir -p "${STAR_OUTPUT_DIR}/qc_reports"
mkdir -p "array_logs"

echo "Config loaded successfully."
