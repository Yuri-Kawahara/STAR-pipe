# STAR-pipe
# STAR-pipe 説明書

### FASTQ → BAM + Count matrix pipeline

> **対象 / Target**  
> ヒト・マウスの paired-end bulk RNA-seq。HPC (SGE) またはローカルで動く。  
> Human/mouse paired-end bulk RNA-seq. Runs on HPC (SGE) or local.

-----

## スクリプト一覧 / Scripts

|スクリプト                             |何をする / What it does                              |
|----------------------------------|-------------------------------------------------|
|`setup.sh`                        |ツールをインストール / Install tools                       |
|`config.sh`                       |パス・変数の一元管理 / Central config — **edit here first**|
|`create_genome_index_hs.sh`       |ヒトのリファレンスDL & STARインデックス作成 / Human ref + index   |
|`create_genome_index_mm.sh`       |マウスのリファレンスDL & STARインデックス作成 / Mouse ref + index  |
|`create_sample_qclist_20260428.sh`|サンプルリストを自動作成 / Auto-generate sample list         |
|`run_qc_trim.sh`                  |QC（FastQC）＋ トリミング（fastp）                         |
|`run_star_align.sh`               |STARアライメント → BAM + カウントテーブル                      |

-----

## ディレクトリ構成 / Directory structure

```
$HOME/
├── Reference/
│   ├── human/          # FASTA / GTF (GRCh38 v49)
│   └── mouse/          # FASTA / GTF (GRCm39 M38)
│
├── gdc_reference/
│   └── star/
│       ├── GRCh38_v49_star_index/   # STARインデックス (human)
│       └── mm39_star_index/         # STARインデックス (mouse)
│
├── fastq/
│   └── zebra/                       # RAW FASTQの置き場
│       ├── mmSample1_R1_L001.fq.gz
│       ├── mmSample1_R2_L001.fq.gz
│       └── trimmed/                 # fastp出力先（自動作成）
│
└── STAR_output/
    └── mouse/                       # STAR出力先
        ├── bam/
        ├── log_star/
        ├── qc_reports/
        └── array_logs/
```

> **⚠ ヒトとマウスはディレクトリを必ず分ける。**  
> Keep human and mouse in completely separate directories.

-----

## 実行順序 / Execution order

```
Step 0  config.sh を編集
Step 1  setup.sh でツールをインストール（初回のみ）
Step 2  インデックス作成（初回のみ）
Step 3  サンプルリスト作成
Step 4  QC & トリミング
Step 5  STARアライメント
```

-----

## Step 0 — config.sh を編集する ← **最初にここだけ**

全スクリプトが `source ./config.sh` でこのファイルを読む。**パス変更はここだけ。**  
All scripts read this file via `source ./config.sh`. Edit paths here only.

```bash
# サンプルIDの先頭で種を自動判別 / Species auto-detection by sample ID prefix
MOUSE_SAMP_KEY="^mm"   # "mm" で始まる → マウス
HUMAN_SAMP_KEY="^Hu"   # "Hu" で始まる → ヒト

BASE_DIR="/home/kawayuri"          # ← 自分のホームに変更

RAW_FASTQ_DIR="${BASE_DIR}/fastq/zebra"   # FASTQのあるディレクトリ
TRIM_DIR="${RAW_FASTQ_DIR}/trimmed"

STAR_INDEX_MM="${BASE_DIR}/gdc_reference/mm39_star_index"
STAR_INDEX_HU="${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index"

GENCODE_GTF_MM="${BASE_DIR}/Reference/mouse/gencode.vM38.primary_assembly.annotation.gtf"
GENCODE_GTF_HU="${BASE_DIR}/Reference/human/gencode.v49.primary_assembly.annotation.gtf"

STAR_OUTPUT_DIR="${BASE_DIR}/STAR_output/mouse"   # ← プロジェクトに合わせて変更

THREADS=16

RAW_SAMPLE_LIST="samples_202604"
STAR_READY_LIST="star_ready_samples.txt"
```

**確認 / Check:**

```bash
source ./config.sh
# → "Config loaded successfully." と表示されれば OK
```

> `STAR_OUTPUT_DIR` 以下のサブディレクトリは config.sh の末尾で `mkdir -p` により自動作成される。

-----

## Step 1 — ツールのインストール（初回のみ）/ Install tools (first time only)

condaで `bio_tools` 環境を作り、FastQC・fastp・STARを一括インストールする。  
Creates a conda env `bio_tools` and installs FastQC, fastp, and STAR.

```bash
bash setup.sh
```

> condaがない場合は先にMinicondaをインストール:  
> https://docs.conda.ai/en/latest/miniconda.html

> HPCで `module load` を使う場合は `setup.sh` は不要。  
> On HPC using `module load`, skip this step.

**確認 / Check:**

```bash
STAR --version
fastqc --version
fastp --version
```

-----

## Step 2 — リファレンス & インデックス作成（初回のみ）/ Build reference & index (first time only)

GENCODEからFASTA・GTFをダウンロードし、STARインデックスを作る。  
Downloads FASTA/GTF from GENCODE and builds the STAR index.

> **ディスク容量の目安 / Disk space required**
> 
> |           |ヒト (GRCh38 v49)|マウス (GRCm39 M38)|
> |-----------|---------------|----------------|
> |FASTA + GTF|~5 GB          |~4 GB           |
> |STARインデックス |~30 GB         |~27 GB          |

### ヒト / Human

`create_genome_index_hs.sh` の先頭にある変数を確認・編集する:

```bash
BASE_DIR="/home/kawayuri"   # ← 変更
THREADS=16
OVERHANG=149                # リード長 - 1 (150bp reads → 149)
USE_CUSTOM_FUSION=false     # 融合遺伝子を追加する場合は true
```

実行:

```bash
# HPC
qsub create_genome_index_hs.sh

# ローカル
bash create_genome_index_hs.sh
```

> スクリプトが自動で行うこと / What the script does automatically:
> 
> 1. GENCODE v49 (FASTA, GTF, transcripts) を EBI からダウンロード（既存ならスキップ）
> 1. STARインデックスを構築
> 1. IGV用 BEDファイルを作成
> 1. `USE_CUSTOM_FUSION=true` の場合は融合遺伝子配列をインデックスに追加

### マウス / Mouse

```bash
qsub create_genome_index_mm.sh
# または
bash create_genome_index_mm.sh
```

**確認 / Check:**

```bash
ls ~/gdc_reference/star/GRCh38_v49_star_index/SAindex   # human
ls ~/gdc_reference/mm39_star_index/SAindex               # mouse
# → ファイルが存在すればOK
```

-----

## Step 3 — サンプルリストの作成 / Create sample list

FASTQディレクトリを走査してサンプルIDの一覧を作る。  
Scans the FASTQ directory and generates a list of sample IDs.

**FASTQファイルの命名規則 / FASTQ naming convention:**

```
{SAMPLE_ID}_R1_{anything}.fq.gz   ← Read 1
{SAMPLE_ID}_R2_{anything}.fq.gz   ← Read 2
```

> サンプルIDの先頭が `mm` → マウス、`Hu` → ヒト として後のSTARステップで自動判別される。

```bash
bash create_sample_qclist_20260428.sh
```

スクリプトが行うこと / What it does:

- `*R1*` ファイルを検索し、対応する `*R2*` の存在を確認する
- ファイル名から `R1` 部分を除いてサンプルIDを抽出する
- ソート済みユニークリストを `samples_202604` に保存する

**確認 / Check:**

```bash
cat samples_202604
wc -l samples_202604   # サンプル数を確認
```

-----

## Step 4 — QC & トリミング / QC & Trimming

FastQCでリードの品質を確認し、fastpでアダプターを除去する。  
Checks read quality with FastQC and removes adapters with fastp.

```bash
# HPC ジョブアレイ（全サンプル一括）/ HPC job array (all samples)
NUM=$(wc -l < samples_202604 | awk '{print $1}')
qsub -t 1-${NUM} run_qc_trim.sh

# ローカルで1サンプルだけテスト / Local single-sample test
bash run_qc_trim.sh mmSample1_L001
```

> トリミング済みファイルが既に存在する場合はスキップされる。  
> Skips automatically if trimmed files already exist.

**出力先 / Output:**

```
STAR_output/mouse/qc_reports/
├── {SAMPLE}_fastqc.html     # FastQCレポート（トリミング前）
├── {SAMPLE}_fastp.html      # fastpレポート
└── {SAMPLE}_fastp.json

fastq/zebra/trimmed/
├── {SAMPLE}_trim_1.fq.gz    # トリミング済み R1
└── {SAMPLE}_trim_2.fq.gz    # トリミング済み R2
```

**確認 / Check:**

```bash
# ファイル数 = サンプル数 × 2 か確認
ls fastq/zebra/trimmed/ | wc -l

# fastpレポートでトリミング率を確認
# Check trimming rate in fastp HTML report
open STAR_output/mouse/qc_reports/SAMPLE_fastp.html
```

-----

## Step 5 — STARアライメント / STAR alignment

トリミング済みリードをゲノムにマッピングする。BAMとカウントテーブルを出力する。  
Maps trimmed reads to the genome. Outputs BAM and read count table.

まず STAR 用のサンプルリストを用意する。  
First, prepare the sample list for STAR:

```bash
# QCに問題がなければそのまま使う / If QC looks fine, use as-is
cp samples_202604 star_ready_samples.txt

# QCに問題があるサンプルは手動で削除してから使う
# Remove samples with QC issues manually before copying
```

実行 / Run:

```bash
# HPC ジョブアレイ / HPC job array
NUM=$(wc -l < star_ready_samples.txt | awk '{print $1}')
qsub -t 1-${NUM} run_star_align.sh

# ローカルで1サンプルだけテスト / Local single-sample test
bash run_star_align.sh mmSample1_L001
```

> サンプルIDの先頭が `mm` → `STAR_INDEX_MM` を使用。  
> サンプルIDの先頭が `Hu` → `STAR_INDEX_HU` を使用。  
> それ以外 → エラーで停止。  
> Species is auto-detected from the sample ID prefix defined in config.sh.

**出力先 / Output:**

```
STAR_output/mouse/
├── bam/
│   ├── {SAMPLE}.Aligned.sortedByCoord.out.bam    # 座標ソート済みBAM
│   ├── {SAMPLE}.Aligned.sortedByCoord.out.bam.bai
│   ├── {SAMPLE}.ReadsPerGene.out.tab              # カウントテーブル
│   └── {SAMPLE}.Chimeric.out.junction             # 融合遺伝子ジャンクション
└── log_star/
    ├── {SAMPLE}.Log.final.out    # マッピング率サマリ ← 必ず確認
    ├── {SAMPLE}.Log.out
    └── {SAMPLE}.SJ.out.tab       # スプライスジャンクション
```

**確認 / Check:**

```bash
# BAMファイル数を確認
ls STAR_output/mouse/bam/*.bam | wc -l

# マッピング率を確認（60%以上が目安）
# Check mapping rate (aim for >60%)
grep "Uniquely mapped reads %" STAR_output/mouse/log_star/*.Log.final.out
```

-----

## カウントテーブルの使い方 / Using ReadsPerGene.out.tab

`ReadsPerGene.out.tab` には3列のカウントがある。  
The file has 3 count columns. Pick the right one for your library type.

|列 / Column|ストランド / Strand  |
|----------|----------------|
|col2      |Unstranded      |
|col3      |Stranded (sense)|
|col4      |Antisense       |

どの列を使うかRで確認する / Check which column to use in R:

```r
counts <- read.table("sample.ReadsPerGene.out.tab", skip=4)
colSums(counts[, 2:4])
# 最も合計が大きい列がそのライブラリに対応する
# The column with the largest sum corresponds to your library type
```

-----

## ヒト ↔ マウス 切り替え / Switching between human and mouse

`config.sh` を変更するだけ。スクリプト本体は触らない。  
Edit `config.sh` only. Do not edit the scripts themselves.

|変数                          |ヒト                         |マウス                        |
|----------------------------|---------------------------|---------------------------|
|`STAR_OUTPUT_DIR`           |`STAR_output/human_project`|`STAR_output/mouse_project`|
|`RAW_SAMPLE_LIST` のIDプレフィックス|`Hu`                       |`mm`                       |


> `run_star_align.sh` は `MOUSE_SAMP_KEY` / `HUMAN_SAMP_KEY` でインデックスを自動選択する。  
> プレフィックスが合っていないとエラーで停止する。

-----

## 融合遺伝子をインデックスに追加する場合 / Adding custom fusion genes to the index

`create_genome_index_hs.sh` の先頭で設定する:

```bash
USE_CUSTOM_FUSION=true
CUSTOM_FUSION_FA="${REF_DIR}custom_fusion_genes.fa"   # 融合遺伝子のFASTA
EXCLUDE_WILDTYPE_GENES="GENE1 GENE2"                  # 野生型を除きたい場合はここに記入
                                                       # Leave empty if not needed
```

> スクリプトが自動で fusion GTF を作り、hybrid genome + hybrid index を構築する。  
> The script auto-generates a fusion GTF and builds a hybrid genome index.

-----

## よくあるエラー / Troubleshooting

|エラー                                  |原因                |対処                                                   |
|-------------------------------------|------------------|-----------------------------------------------------|
|`SAindex not found`                  |インデックス未完成         |Step 2 を再実行                                          |
|`FASTQ files not found`              |パスかファイル名の誤り       |`ls ${RAW_FASTQ_DIR}` で確認                            |
|`ERROR: Unknown species prefix`      |サンプルIDのプレフィックス不一致 |`config.sh` の `MOUSE_SAMP_KEY` / `HUMAN_SAMP_KEY` を確認|
|`Config loaded` が出ない                 |`config.sh` のパスが違う|スクリプトと同じディレクトリで実行しているか確認                             |
|STAR: `genome files are inconsistent`|インデックスが壊れている      |インデックスを削除して再構築                                       |
|fastp failed                         |メモリ不足 or ファイル破損   |`md5sum` でファイル整合性を確認                                 |

-----

*Last updated: 2026-04-30*
