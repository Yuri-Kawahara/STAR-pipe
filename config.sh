#!/bin/bash

# --- プロジェクト基本ディレクトリ ---
BASE_DIR="/Users/Documents"

# --- 入力データパス ---
# 生のFASTQが格納されている場所
RAW_FASTQ_DIR="${BASE_DIR}/RNA..."
# トリミング済みFASTQの出力先
TRIM_DIR="${RAW_FASTQ_DIR}/qcresult"

# --- リファレンス・インデックスパス ---
# GTFファイルのフルパス
GENCODE_GTF="${BASE_DIR}/Reference/mouse/gencode.vM38.primary_assembly.annotation.gtf"

# STAR インデックスディレクトリ (マウス用とヒト用を定義)
STAR_INDEX_MM="${BASE_DIR}/gdc_reference/mm39_star_index"
STAR_INDEX_HU="${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index"

# Salmon インデックスディレクトリ (必要に応じてこちらも追加可能)
SALMON_INDEX_DIR="${BASE_DIR}/gdc_reference/salmon/gencode.v36.salmon_index"

# --- 出力先ディレクトリ ---
STAR_OUTPUT_DIR="${BASE_DIR}/STAR_output/bulk_202604"
SALMON_OUTPUT_DIR="${BASE_DIR}/SALMON_output/bulk_202604"

# --- 実行パラメータ ---
THREADS=16

# --- リストファイル名 ---
RAW_SAMPLE_LIST="samples_202604"
STAR_READY_LIST="star_ready_samples.txt"

# --- ディレクトリの自動作成 ---
mkdir -p "${TRIM_DIR}"
mkdir -p "${STAR_OUTPUT_DIR}/bam"
mkdir -p "${STAR_OUTPUT_DIR}/log_star"
mkdir -p "${STAR_OUTPUT_DIR}/qc_reports"
mkdir -p "${SALMON_OUTPUT_DIR}"
mkdir -p "array_logs"

echo "Config loaded successfully."
