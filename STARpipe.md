# RNA-seq Pipeline: FASTQ → Count Matrix

### STAR mapping — Setup & Execution Guide

> **対象 / Target**  
> Linux (HPC) · macOS での実行を想定。  
> Assumes Linux HPC or macOS.

-----

## 0. スクリプト一覧 / Script overview

|#|Script                            |何をするか / What it does                             |
|-|----------------------------------|-------------------------------------------------|
|1|`setup.sh`                        |ツールのインストール / Install tools                       |
|2|`config.sh`                       |パス・パラメータの一元管理 / Central config (edit here first!)|
|3|`create_genome_index_hs.sh`       |ヒト用リファレンス DL & インデックス作成 / Human ref + index      |
|3|`create_genome_index_mm.sh`       |マウス用リファレンス DL & インデックス作成 / Mouse ref + index     |
|4|`create_igv_bed.sh`               |IGV 用 BED ファイル作成 / BED for IGV                   |
|5|`create_sample_qclist_20260428.sh`|サンプルリスト自動生成 / Auto-generate sample list          |
|6|`run_qc_trim.sh`                  |FastQC + fastp (QC & トリミング)                      |
|7|`run_star_align.sh`               |STAR アライメント / Alignment                          |


> **⚠ 旧 `fastq_pipe_2strand_STAR.sh` / `fastq_pipe_2strand_Salmon.sh` は廃止。**  
> QC と STAR が `run_qc_trim.sh` / `run_star_align.sh` に分離された。  
> Salmon は現在このパイプラインに含まれない。

-----

## 1. ディレクトリ構成 / Directory structure

> **種が混在する場合はディレクトリを必ず分ける！**  
> Keep human and mouse in **completely separate directories**.

```
$HOME/
├── Reference/
│   ├── human/          ← FASTA / GTF (human)
│   └── mouse/          ← FASTA / GTF (mouse)
│
├── gdc_reference/
│   └── star/
│       ├── GRCh38_v49_star_index/    ← STAR index (human)
│       └── mm39_star_index/          ← STAR index (mouse)
│
├── fastq/
│   └── zebra/                        ← RAW_FASTQ_DIR (config.sh で設定)
│       ├── mmSample1_R1_L001.fq.gz
│       ├── mmSample1_R2_L001.fq.gz
│       └── trimmed/                  ← fastp 出力先
│
└── STAR_output/
    └── mouse/                        ← STAR_OUTPUT_DIR (config.sh で設定)
        ├── bam/
        ├── log_star/
        └── qc_reports/
```

-----

## 2. 環境構築 / Environment setup

### 2-1. ツールのインストール / Install tools

`setup.sh` を実行するだけ。

```bash
bash setup.sh
```

conda がない場合は先に Miniconda をインストール:  
https://docs.conda.io/en/latest/miniconda.html

### 2-2. ツールバージョン確認 / Verify tool versions

```bash
STAR --version       # 推奨: 2.7.x
fastqc --version
fastp --version
```

### 2-3. HPC でモジュールを使う場合 / On HPC cluster

```bash
module load fastqc
module load fastp
module load star
```

> `run_qc_trim.sh` / `run_star_align.sh` の中に `module load` が書かれているので、  
> HPC ユーザーは conda activate は不要。

-----

## 3. config.sh の設定 ← **必ず最初に編集する**

**全スクリプトが `source ./config.sh` で読み込む。パスはここだけ変える。**  
All scripts read this file. Edit paths here only.

```bash
# --- サンプルIDのプレフィックスによる種の自動判別 ---
MOUSE_SAMP_KEY="^mm"    # サンプルIDが "mm" で始まる → マウス
HUMAN_SAMP_KEY="^Hu"    # サンプルIDが "Hu" で始まる → ヒト

# --- プロジェクト基本ディレクトリ ---
BASE_DIR="/home/kawayuri"          # ← 自分のホームに変更

# --- 入力データ ---
RAW_FASTQ_DIR="${BASE_DIR}/fastq/zebra"   # ← FASTQのあるディレクトリ

# --- STAR インデックス ---
STAR_INDEX_MM="${BASE_DIR}/gdc_reference/mm39_star_index"
STAR_INDEX_HU="${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index"

# --- GTF ---
GENCODE_GTF_MM="${BASE_DIR}/Reference/mouse/gencode.vM38.primary_assembly.annotation.gtf"
GENCODE_GTF_HU="${BASE_DIR}/Reference/human/gencode.v49.primary_assembly.annotation.gtf"

# --- 出力先 ---
STAR_OUTPUT_DIR="${BASE_DIR}/STAR_output/mouse"   # ← プロジェクトに合わせて変更

# --- スレッド数 ---
THREADS=16

# --- サンプルリストファイル名 ---
RAW_SAMPLE_LIST="samples_202604"
STAR_READY_LIST="star_ready_samples.txt"
```

> `STAR_OUTPUT_DIR` のサブディレクトリ (`bam/`, `log_star/`, `qc_reports/`, `array_logs/`) は  
> config.sh の末尾で `mkdir -p` により自動作成される。手動作成は不要。

**設定後の確認 / Check after editing:**

```bash
source ./config.sh
# → "Config loaded successfully." と表示されれば OK
echo $RAW_FASTQ_DIR
echo $STAR_INDEX_MM
```

-----

## 4. リファレンスのダウンロード & インデックス作成

### 4-1. ディスク容量の目安 / Disk space

|データ            |ヒト (GRCh38 v49)|マウス (GRCm39 M38)|
|---------------|---------------|----------------|
|ゲノム FASTA      |~3.2 GB        |~2.8 GB         |
|GTF            |~1.5 GB        |~1.2 GB         |
|**STAR インデックス**|**~30 GB**     |**~27 GB**      |
|**合計目安**       |**~35 GB**     |**~31 GB**      |


> STAR インデックスが最も大きい。ホームのクォータを先に確認。  
> Check your home directory quota before running.

### 4-2. ヒト / Human (GRCh38 / GENCODE v49)

`create_genome_index_hs.sh` 冒頭の設定を編集:

```bash
BASE_DIR="/home/YOUR_USERNAME"   # ← 変更
THREADS=16
OVERHANG=149    # リード長 - 1 (150bp reads → 149)
```

実行:

```bash
# HPC
qsub create_genome_index_hs.sh

# ローカル
bash create_genome_index_hs.sh
```

### 4-3. マウス / Mouse (GRCm39 / GENCODE M38)

```bash
qsub create_genome_index_mm.sh
# または
bash create_genome_index_mm.sh
```

### 4-4. 完了確認 / Verify

```bash
# SAindex ファイルが存在すれば OK
ls ~/gdc_reference/star/GRCh38_v49_star_index/SAindex   # human
ls ~/gdc_reference/mm39_star_index/SAindex               # mouse
```

-----

## 5. サンプルリストの作成

### 5-1. FASTQファイルの命名規則 / Naming convention

`create_sample_qclist_20260428.sh` は **R1/R2 を含むファイル名** を自動検出する。

```
{SAMPLE_ID}_R1_{anything}.fq.gz   ← Read 1
{SAMPLE_ID}_R2_{anything}.fq.gz   ← Read 2
```

> サンプルIDの先頭文字でヒト/マウスを区別する（`config.sh` の `MOUSE_SAMP_KEY` / `HUMAN_SAMP_KEY`）。  
> デフォルト: `mm` → マウス、`Hu` → ヒト。

### 5-2. 実行 / Run

```bash
bash create_sample_qclist_20260428.sh
```

何をするか:

- `RAW_FASTQ_DIR` 内で `*R1*` ファイルを検索し、対応する `*R2*` の存在を確認
- ファイル名から R1/R2 部分を除いてサンプルIDを抽出
- ソート済みユニークリストを `samples_202604` に保存

**確認 / Check:**

```bash
cat samples_202604
wc -l samples_202604   # サンプル数を確認
```

### 5-3. STAR 実行用リストの準備 / Prepare STAR-ready list

QC & トリミングが終わったサンプルだけを `star_ready_samples.txt` に入れる。  
`run_star_align.sh` はこちらを参照する。

```bash
# 全サンプルをそのまま使う場合
cp samples_202604 star_ready_samples.txt

# トリミング済みファイルの存在で自動フィルタする場合
while read id; do
  if [ -f "${BASE_DIR}/fastq/zebra/trimmed/${id}_trim_1.fq.gz" ]; then
    echo "$id"
  fi
done < samples_202604 > star_ready_samples.txt

wc -l star_ready_samples.txt
```

-----

## 6. Step 1: QC & トリミング (run_qc_trim.sh)

### FastQC + fastp でリードの品質確認とアダプター除去を行う。

**実行 / Run:**

```bash
# HPC ジョブアレイ (全サンプル一括)
NUM=$(wc -l < samples_202604 | awk '{print $1}')
qsub -t 1-${NUM} run_qc_trim.sh

# ローカルで1サンプルだけテスト
bash run_qc_trim.sh sample_id_here
```

> スクリプト内部では `source ./config.sh` でパスを読み込む。  
> トリミング済みファイルが既に存在する場合はスキップされる (`if [ ! -f ... ]`)。

**出力先 / Output:**

```
STAR_output/mouse/qc_reports/
├── {SAMPLE}_fastqc.html       ← FastQC レポート (トリミング前)
├── {SAMPLE}_fastp.html        ← fastp レポート
└── {SAMPLE}_fastp.json

fastq/zebra/trimmed/
├── {SAMPLE}_trim_1.fq.gz      ← トリミング済み R1
└── {SAMPLE}_trim_2.fq.gz      ← トリミング済み R2
```

**確認 / Check:**

```bash
ls fastq/zebra/trimmed/ | wc -l    # ファイル数 = サンプル数 × 2 か確認
# fastp レポートで trimming rate を確認
open STAR_output/mouse/qc_reports/SAMPLE_fastp.html
```

-----

## 7. Step 2: STAR アライメント (run_star_align.sh)

### トリミング済みリードをゲノムにマッピングし、BAM とカウントテーブルを出力する。

**ヒト/マウスの自動判別 / Auto species detection:**  
サンプルIDの先頭が `mm` → マウス index を使用  
サンプルIDの先頭が `Hu` → ヒト index を使用  
それ以外 → エラーで停止

**実行 / Run:**

```bash
# HPC ジョブアレイ
NUM=$(wc -l < star_ready_samples.txt | awk '{print $1}')
qsub -t 1-${NUM} run_star_align.sh

# ローカルで1サンプルだけテスト
bash run_star_align.sh mmSample1_L001
```

**主要 STAR パラメータ / Key parameters:**

|パラメータ                    |値                           |説明                                 |
|-------------------------|----------------------------|-----------------------------------|
|`--twopassMode Basic`    |Basic                       |2パスモード。スプライスジャンクションの検出感度が上がる       |
|`--outFilterMultimapNmax`|20                          |マルチマップ許容数（デフォルト10より高め）             |
|`--outFilterMismatchNmax`|10                          |許容ミスマッチ数                           |
|`--alignIntronMax`       |300000                      |イントロン最大長 (bp)                      |
|`--quantMode GeneCounts` |-                           |遺伝子カウントを `ReadsPerGene.out.tab` に出力|
|`--chimSegmentMin`       |15                          |キメラ (融合遺伝子) 検出の最小セグメント長            |
|`--chimOutType`          |Junctions WithinBAM SoftClip|キメラ読みを BAM に含める                    |

**出力先 / Output:**

```
STAR_output/mouse/
├── bam/
│   ├── {SAMPLE}.Aligned.sortedByCoord.out.bam
│   ├── {SAMPLE}.Aligned.sortedByCoord.out.bam.bai  ← samtools index 要
│   └── {SAMPLE}.ReadsPerGene.out.tab   ← カウントテーブル
└── log_star/
    ├── {SAMPLE}.Log.final.out    ← マッピング率サマリ
    ├── {SAMPLE}.Log.out
    └── {SAMPLE}.SJ.out.tab       ← スプライスジャンクション
```

**確認 / Check:**

```bash
# BAM ファイル数の確認
ls STAR_output/mouse/bam/*.bam | wc -l

# マッピング率の確認 (60% 以上が目安)
grep "Uniquely mapped reads %" STAR_output/mouse/log_star/*.Log.final.out
```

-----

## 8. カウントテーブルのストランド確認

`ReadsPerGene.out.tab` には3列のカウントがある。

|列   |意味              |
|----|----------------|
|col2|Unstranded      |
|col3|Stranded (sense)|
|col4|Antisense       |

どの列を使うか確認する:

```bash
# R での確認
counts <- read.table("sample.ReadsPerGene.out.tab", skip=4)
colSums(counts[, 2:4])
# 最も大きい列がそのライブラリのストランドに対応
```

> 最も合計が大きい列を DESeq2 / edgeR に渡す。

-----

## 9. IGV での可視化

IGV BED ファイルはインデックス作成時に自動生成される。  
マウス単体で別途必要な場合:

```bash
bash create_igv_bed.sh
```

IGV 読み込み手順:

```
1. Genomes > Load Genome from File
   → GRCm39.primary_assembly.genome.fa  (mouse)
   → GRCh38.primary_assembly.genome.fa  (human)

2. File > Load from File
   → mouse_transcripts.bed  or  human_transcripts.bed

3. 検索ボックスで遺伝子名を入力 (例: Trp53, Myc)
```

-----

## 10. 実行順序まとめ / Execution order

```
Step 0  config.sh を編集 ← まずここ
        source ./config.sh  # "Config loaded successfully." を確認

Step 1  ツールインストール (初回のみ)
        bash setup.sh

Step 2  リファレンス & インデックス作成 (初回のみ)
        bash create_genome_index_hs.sh   # human
        bash create_genome_index_mm.sh   # mouse
        → ls ~/gdc_reference/star/*/SAindex で確認

Step 3  サンプルリスト作成
        bash create_sample_qclist_20260428.sh
        → cat samples_202604 で目視確認

Step 4  QC & トリミング
        qsub -t 1-N run_qc_trim.sh
        → trimmed/ にファイルが揃っているか確認

Step 5  STAR 実行用リスト作成
        cp samples_202604 star_ready_samples.txt  # (または絞り込み)

Step 6  STAR アライメント
        qsub -t 1-N run_star_align.sh
        → Log.final.out でマッピング率を確認
```

-----

## 11. ヒト ↔ マウス 切り替えチェックリスト

`config.sh` で変更するのみ。スクリプト本体は触らない。

|変数                                 |ヒト                         |マウス                        |
|-----------------------------------|---------------------------|---------------------------|
|`STAR_INDEX_HU` / `STAR_INDEX_MM`  |`GRCh38_v49_star_index`    |`mm39_star_index`          |
|`GENCODE_GTF_HU` / `GENCODE_GTF_MM`|`gencode.v49...gtf`        |`gencode.vM38...gtf`       |
|`STAR_OUTPUT_DIR`                  |`STAR_output/human_project`|`STAR_output/mouse_project`|
|`RAW_SAMPLE_LIST` のIDプレフィックス       |`Hu`                       |`mm`                       |


> `run_star_align.sh` はサンプルIDの先頭を `config.sh` の `MOUSE_SAMP_KEY` / `HUMAN_SAMP_KEY`  
> と照合して index を自動選択する。プレフィックスが合っていないとエラーで停止する。

-----

## 12. よくあるエラーと対処 / Troubleshooting

|エラー                                  |原因                |対処                                                   |
|-------------------------------------|------------------|-----------------------------------------------------|
|`SAindex not found`                  |インデックス未完成         |Step 2 を再実行。ログ確認                                     |
|`FASTQ files not found`              |パスかファイル名の誤り       |`ls ${RAW_FASTQ_DIR}` で確認                            |
|`ERROR: Unknown species prefix`      |サンプルIDのプレフィックス不一致 |`config.sh` の `MOUSE_SAMP_KEY` / `HUMAN_SAMP_KEY` を確認|
|fastp failed                         |メモリ不足 or ファイル破損   |`md5sum` でファイル整合性を確認                                 |
|STAR: `genome files are inconsistent`|インデックスが壊れている      |インデックスを削除して再構築                                       |
|`Config loaded` が出ない                 |`config.sh` のパスが違う|スクリプトと同じディレクトリで実行しているか確認                             |

-----

*Last updated: 2026-04-29*