# RNA-seq Pipeline: FASTQ to Count Matrix

### STAR / Salmon — Setup & Execution Guide

> **対象読者 / Target reader**  
> Linux (HPC/local) · macOS での実行を想定。Windows は WSL2 推奨。  
> Assumes Linux (HPC or local) or macOS. Windows users: use WSL2.

-----

## 0. スクリプト一覧 / Script overview

|#|Script                            |何をするか / What it does                               |
|-|----------------------------------|---------------------------------------------------|
|1|`setup.sh`                        |ツールのインストール / Install tools                         |
|2|`create_genome_index_hs.sh`       |ヒト用リファレンス DL & インデックス作成 / Human ref + index        |
|2|`create_genome_index_mm.sh`       |マウス用リファレンス DL & インデックス作成 / Mouse ref + index       |
|3|`create_igv_bed.sh`               |IGV 表示用 BED ファイル作成 / BED for IGV (mouse standalone)|
|4|`create_sample_qclist_20260428.sh`|サンプルリスト自動生成 / Auto-generate sample list            |
|5|`fastq_pipe_2strand_STAR.sh`      |QC → Trim → STAR アライメント / QC → Trim → Align        |
|6|`fastq_pipe_2strand_Salmon.sh`    |QC → Trim → Salmon 定量 / QC → Trim → Quantify       |

-----

## 1. ディレクトリ構成 / Directory structure

:::message alert
**種が混在する場合はディレクトリを必ず分けること！**  
If you analyze multiple species (e.g., human + mouse), keep them in **completely separate directories**.  
インデックスやカウントファイルを混在させると後工程（tximport 等）で取り返しがつかないミスになる。
:::

```
$HOME/
├── Reference/
│   ├── human/          ← ヒト用 FASTA / GTF / Salmon index
│   │   └── igv/
│   └── mouse/          ← マウス用 FASTA / GTF / Salmon index
│       └── igv/
│
├── gdc_reference/
│   ├── star/
│   │   ├── GRCh38_v49_star_index/    ← STAR index (human)
│   │   └── mm39_star_index/          ← STAR index (mouse)
│   └── salmon/
│       └── gencode.v49.human_salmon_index/
│
├── fastq/
│   └── YOUR_PROJECT/
│       ├── sample1_1.fq.gz
│       ├── sample1_2.fq.gz
│       └── trimmed/
│
├── STAR_output/
│   └── YOUR_PROJECT/
│       ├── bam/
│       ├── log_star/
│       └── qc_reports/
│
└── SALMON_output/
    └── YOUR_PROJECT/
```

-----

## 2. 環境構築 / Environment setup

### 2-1. HPC (クラスタ) の場合 / On HPC cluster

```bash
# 利用可能なモジュールを確認する / Check available modules
module avail star
module avail salmon
module avail fastqc
module avail fastp

# ロードする / Load them
module use /usr/local/package/modulefiles
module load star
module load salmon
module load fastqc
module load fastp
```

> バージョンが古い場合や conda を使いたい場合は 2-2 へ。  
> If versions are outdated or you prefer conda, see 2-2.

-----

### 2-2. conda 環境を使う場合 / Using conda

`setup.sh` を実行するだけ / Just run `setup.sh`:

```bash
bash setup.sh
```

内容は以下の通り:

```bash
# setup.sh の中身 / Content of setup.sh
conda create -n bio_tools -c bioconda -c conda-forge \
    fastqc \
    fastp \
    star -y

# Salmon は別途追加推奨
conda install -n bio_tools -c bioconda salmon
```

> conda がない場合は先に Miniconda をインストール:  
> Install Miniconda first if you don’t have conda:  
> https://docs.conda.io/en/latest/miniconda.html

パイプライン実行前に環境を有効化する / Activate before running:

```bash
conda activate bio_tools
```

-----

### 2-3. ツールバージョン確認 / Verify tool versions

```bash
STAR --version       # 推奨: 2.7.x
salmon --version     # 推奨: 1.10.x
fastqc --version
fastp --version
python3 --version    # 3.8 以上必要 (IGV BED 作成スクリプト用)
```

-----

### 2-4. Mac の注意点 / macOS notes

macOS の標準 `bash` は **version 3.2** で古い (`for` ループの `(( ))` 等が動作しない場合がある)。

```bash
# bash バージョン確認
bash --version

# Homebrew で新しい bash をインストール (推奨)
brew install bash

# ツール類も Homebrew or conda で入れる
brew install fastqc fastp
```

`wc -l` の出力に余分なスペースが含まれる問題は `create_sample_qclist_20260428.sh` で対処済み (`awk '{print $1}'` でトリム)。

-----

### 2-5. Windows の場合 / Windows

**WSL2 (Ubuntu)** を使えばほぼ Linux と同じ手順で動く。  
WSL2 上で conda または apt でツールを導入する。

```powershell
# PowerShell で WSL2 インストール
wsl --install
```

-----

## 3. リファレンスのダウンロード & インデックス作成

### 3-1. ディスク容量の目安 / Disk space requirements

|データ             |ヒト (GRCh38 v49)|マウス (GRCm39 M38)|
|----------------|---------------|----------------|
|ゲノム FASTA (解凍後) |~3.2 GB        |~2.8 GB         |
|トランスクリプトーム FASTA|~0.2 GB        |~0.2 GB         |
|GTF             |~1.5 GB        |~1.2 GB         |
|**STAR インデックス** |**~30 GB**     |**~27 GB**      |
|Salmon インデックス   |~2 GB          |~1.5 GB         |
|IGV BED         |~0.1 GB        |~0.1 GB         |
|**合計目安**        |**~37 GB**     |**~33 GB**      |

:::message
STAR インデックスが最も大きい。ホームディレクトリのクォータに注意。  
STAR index is the largest. Check your home directory quota first.
:::

-----

### 3-2. ヒトの場合 / Human (GRCh38 / GENCODE v49)

`create_genome_index_hs.sh` の冒頭の **設定項目** を自分の環境に合わせて書き換える:

```bash
### ============================================================
### — !! 設定項目 !! —  ← ここだけ変更する / Change only here
### ============================================================
BASE_DIR="/home/YOUR_USERNAME"          # ← 自分のホームに変更

REF_DIR=${BASE_DIR}/Reference/human/
SALMON_INDEX=${BASE_DIR}/gdc_reference/salmon/gencode.v49.human_salmon_index/
STAR_INDEX=${BASE_DIR}/gdc_reference/star/GRCh38_v49_star_index/

THREADS=16        # 使えるコア数に合わせる
OVERHANG=149      # リード長 - 1 (150bp reads → 149, 100bp reads → 99)
```

実行 / Run:

```bash
# HPC の場合 / On HPC
qsub create_genome_index_hs.sh

# ローカルの場合 / On local
bash create_genome_index_hs.sh
```

処理内容:

1. GENCODE v49 ファイルのダウンロード (transcripts, genome, GTF)
1. STAR インデックスの構築 (~30〜60 分)
1. IGV 用 BED ファイルの作成

> **⚠ Salmon インデックスはスクリプト内でコメントアウト中。**  
> Salmon を使う場合は `### Step 2` のコメントを外すこと。

-----

### 3-3. マウスの場合 / Mouse (GRCm39 / GENCODE M38)

`create_genome_index_mm.sh` の設定を変更:

```bash
### --- パス設定 ---
REF_DIR=${BASE_DIR}/Reference/mouse/    # ← human → mouse に変更

MOUSE_GENOME="${REF_DIR}GRCm39.primary_assembly.genome.fa"
MOUSE_GTF="${REF_DIR}gencode.vM38.primary_assembly.annotation.gtf"

STAR_INDEX=${BASE_DIR}/gdc_reference/mm39_star_index/
THREADS=16
```

ダウンロード URL はスクリプト内の `wget` 行で確認できる (GENCODE M38)。

実行:

```bash
qsub create_genome_index_mm.sh
# または
bash create_genome_index_mm.sh
```

> マウス単体で IGV BED が必要な場合は `create_igv_bed.sh` を別途実行:
> 
> ```bash
> bash create_igv_bed.sh
> ```

-----

### 3-4. 完了確認 / Verify index creation

```bash
# STAR インデックスが正常に作成されたか確認
# Human
ls ~/gdc_reference/star/GRCh38_v49_star_index/SAindex

# Mouse
ls ~/gdc_reference/mm39_star_index/SAindex

# ファイルが存在すれば OK
```

-----

## 4. サンプルリストの作成

### 4-1. FASTQファイルの命名規則 / FASTQ naming convention

このパイプラインは以下の命名規則を前提とする:

```
{SAMPLE_ID}_1.fq.gz    ← Read 1
{SAMPLE_ID}_2.fq.gz    ← Read 2
```

> `_R1_001.fastq.gz` のような形式の場合はリネームするかスクリプトのパターンを変更する。

-----

### 4-2. create_sample_qclist_20260428.sh の設定

```bash
### --- 設定項目 ---
# フルパスで指定する / Use full path
FASTQ_DIR="/Users/your_username/path/to/fastq"   # ← 変更

OUTPUT_LIST="samples_202604"                       # ← 出力ファイル名
```

実行:

```bash
bash create_sample_qclist_20260428.sh
```

スクリプトが行うこと:

- `_1` と `_2` のペアを自動検出 (1文字違いを検索するロジック)
- 重複サンプル ID を `duplicate_warning.log` にサイレント記録
- ソート済みのユニークリストを出力

出力例:

```
sample_A
sample_B
sample_C
```

確認:

```bash
cat samples_202604
wc -l samples_202604   # サンプル数を確認
```

-----

## 5. パイプライン実行

### 5-1. STAR パイプライン (fastq_pipe_2strand_STAR.sh)

**Step 1: 設定を書き換える**

```bash
### --- 2. 変数の設定 ---
SAMPLE_LIST="/home/YOUR_USERNAME/fastq/YOUR_PROJECT/samples_202604"  # ← 変更

STAR_INDEX_DIR="/home/YOUR_USERNAME/gdc_reference/star/GRCh38_v49_star_index"
#               マウスの場合 → gdc_reference/mm39_star_index

RAW_FASTQ_DIR="/home/YOUR_USERNAME/fastq/YOUR_PROJECT/"   # ← 変更
OUTPUT_DIR="/home/YOUR_USERNAME/STAR_output/YOUR_PROJECT/"  # ← 変更
```

**Step 2: 実行**

```bash
# HPC ジョブアレイとして全サンプル一括実行
NUM=$(wc -l < samples_202604)
qsub -t 1-${NUM} fastq_pipe_2strand_STAR.sh

# ローカルで1サンプルだけ試す場合
SGE_TASK_ID=1 bash fastq_pipe_2strand_STAR.sh
```

-----

#### STAR パラメータ解説 / STAR parameters explained

```bash
STAR \
    --runThreadN ${THREADS} \
    --genomeDir ${STAR_INDEX_DIR} \
    --readFilesIn ${TRIM_FASTQ_1} ${TRIM_FASTQ_2} \
    --readFilesCommand zcat \          # gzip 圧縮 FASTQ を直接読む
    --outFileNamePrefix ${BAM_DIR}/${EXP_ID}. \
    
    # ── アライメント精度 ──────────────────────────────
    --twopassMode Basic \
    # 【推奨】2パスモード: 1回目で発見したスプライスジャンクションを
    # 2回目のアライメントに活用。新規スプライシングの検出感度が上がる。
    # 2-pass mode: use splice junctions found in pass 1 to improve pass 2.
    
    --outFilterMultimapNmax 20 \
    # マルチマップリードを最大何箇所まで許容するか（デフォルト: 10）
    # 融合遺伝子解析では高めにすることがある
    # Max number of loci a read is allowed to map to (default: 10)
    
    --alignSJDBoverhangMin 1 \
    # データベース由来スプライスジャンクションのオーバーハング最小値
    # 1 にすると既知ジャンクションでは 1bp でもマップされる
    # Minimum overhang for annotated junctions (1 = permissive)
    
    --outFilterMismatchNmax 10 \
    # 許容するミスマッチ塩基数の最大値
    # ゼブラフィッシュやマウスへのヒト細胞マッピングでは高めにすることも
    # Max number of mismatches per read pair
    
    --alignIntronMax 300000 \
    # イントロンの最大長 (bp)。哺乳類は 300,000〜500,000 が一般的
    # Max intron size in bp (mammals: 300,000–500,000)
    
    --alignMatesGapMax 300000 \
    # ペアエンドのリード間最大ゲノム距離
    # Max genomic gap between mates (paired-end)
    
    --sjdbScore 2 \
    # スプライスジャンクション由来アライメントへのボーナススコア
    # Bonus score for reads crossing splice junctions
    
    --genomeLoad NoSharedMemory \
    # ゲノムをプロセス間で共有しない（ジョブアレイでは通常これを使う）
    # Don't share genome in memory across processes (safe for job arrays)
    
    # ── マルチマップフィルタ ──────────────────────────
    --outFilterMatchNminOverLread 0.33 \
    # マッチ塩基数 / リード長 の最小比 (デフォルト: 0.66)
    # 0.33 に下げるとショートリードや末端が低品質なリードでもマップされやすい
    # Min ratio of matched bases to read length (lowered from default 0.66)
    
    --outFilterScoreMinOverLread 0.33 \
    # アライメントスコア / リード長 の最小比
    # Min ratio of alignment score to read length

    # ── 出力形式 ──────────────────────────────────────
    --outSAMtype BAM SortedByCoordinate \
    # ゲノム座標でソートされた BAM ファイルを出力
    # Output coordinate-sorted BAM
    
    --outSAMunmapped Within \
    # マップされなかったリードも BAM に含める（QC・デバッグに有用）
    # Keep unmapped reads in BAM (useful for QC)
    
    --outSAMattributes Standard \
    # 標準的な SAM タグを付与 (NH, HI, NM, MD, AS)
    # Add standard SAM tags
    
    --quantMode GeneCounts
    # 遺伝子ごとのリードカウントを ReadsPerGene.out.tab に出力
    # (unstranded / stranded / antisense の3列)
    # Output per-gene read counts to ReadsPerGene.out.tab
    # (3 columns: unstranded / stranded / antisense)
```

:::details ストランド情報の確認 / How to check strandedness

`ReadsPerGene.out.tab` の上部4行を確認する:

```bash
head -4 sample.ReadsPerGene.out.tab
# N_unmapped    ...
# N_multimapping ...
# N_noFeature   ...
# N_ambiguous   ...
```

その後の数値を合計して、col2 (stranded) か col3 (antisense) のどちらが全体に占める割合が高いかで判断。

```r
# R での確認例
counts <- read.table("sample.ReadsPerGene.out.tab", skip=4)
colSums(counts[,2:4])
# 最も大きい列がそのライブラリのストランドに対応
```

:::

-----

### 5-2. Salmon パイプライン (fastq_pipe_2strand_Salmon.sh)

**設定変更箇所:**

```bash
SAMPLE_LIST="..."        # ← STAR と同じリストを使えばよい

SALMON_INDEX_DIR="/home/YOUR_USERNAME/gdc_reference/salmon/gencode.v49.human_salmon_index"
#                  マウスの場合 → gencode.vM38.M_salmon_index

RAW_FASTQ_DIR="..."
OUTPUT_DIR="..."
```

**実行:**

```bash
NUM=$(wc -l < samples_202604)
qsub -t 1-${NUM} fastq_pipe_2strand_Salmon.sh

# ローカル実行
SGE_TASK_ID=1 bash fastq_pipe_2strand_Salmon.sh
```

**Salmon quant パラメータ:**

```bash
salmon quant \
    -i ${SALMON_INDEX_DIR} \   # インデックスディレクトリ
    -l A \                     # ライブラリタイプ自動検出 (A = auto)
    -1 ${TRIM_FASTQ_1} \
    -2 ${TRIM_FASTQ_2} \
    -p ${THREADS} \
    --validateMappings \       # より厳密なマッピング検証（推奨）
    --gcBias \                 # GC バイアス補正（推奨: ライブラリ準備バイアスを補正）
    -o ${OUTPUT_DIR}/${EXP_ID}_quant
```

-----

### 5-3. ヒト ↔ マウスの切り替えチェックリスト

パイプラインをヒトからマウスへ（またはその逆に）切り替えるとき、変更が必要な変数一覧:

|変数                |ヒト (Human)                                   |マウス (Mouse)                                   |
|------------------|---------------------------------------------|----------------------------------------------|
|`STAR_INDEX_DIR`  |`GRCh38_v49_star_index`                      |`mm39_star_index`                             |
|`SALMON_INDEX_DIR`|`gencode.v49.human_salmon_index`             |`gencode.vM38.M_salmon_index`                 |
|`OUTPUT_DIR`      |`STAR_output/human_project/`                 |`STAR_output/mouse_project/`                  |
|GTF (tximport 用)  |`gencode.v49.primary_assembly.annotation.gtf`|`gencode.vM38.primary_assembly.annotation.gtf`|

-----

## 6. IGV での可視化

IGV BED ファイルはインデックス作成時に自動生成される。マウス単体の場合のみ `create_igv_bed.sh` を別途実行する。

```bash
# マウス用 BED が未作成の場合
bash create_igv_bed.sh
```

IGV 読み込み手順:

```
1. Genomes > Load Genome from File
   → GRCh38.primary_assembly.genome.fa  (human)
   → GRCm39.primary_assembly.genome.fa  (mouse)

2. File > Load from File
   → human_transcripts.bed  or  mouse_transcripts.bed
     (BED12: エキソン/イントロン構造が表示される)

3. 検索ボックスで遺伝子名を入力
   例: TP53, MYC (human) / Trp53, Myc (mouse)
```

-----

## 7. 実行順序まとめ / Execution order summary

```
Step 1  環境構築
        bash setup.sh
        ↓ conda activate bio_tools (毎回必要)

Step 2  リファレンス + インデックス作成 (初回のみ / First time only)
        bash create_genome_index_hs.sh   # ヒト
        bash create_genome_index_mm.sh   # マウス
        ↓ SAindex ファイルの存在を確認してから次へ

Step 3  サンプルリスト作成
        ① FASTQ_DIR のパスを編集
        bash create_sample_qclist_20260428.sh
        ↓ cat samples_202604 で内容を目視確認

Step 4  アライメント or 定量
        ② STAR_INDEX_DIR / SALMON_INDEX_DIR・パスを編集
        qsub -t 1-N fastq_pipe_2strand_STAR.sh
        # または
        qsub -t 1-N fastq_pipe_2strand_Salmon.sh
        ↓ ログファイルでエラーがないことを確認

Step 5  (任意) IGV BED 作成
        bash create_igv_bed.sh   # マウスのみ必要な場合
```

:::message
**各ステップで確認してから次へ進むこと。**  
Verify each step before proceeding to the next.

- Step 2 完了確認: `ls ~/gdc_reference/star/*/SAindex`
- Step 3 完了確認: `wc -l samples_202604`
- Step 4 完了確認: `ls STAR_output/*/bam/*.bam | wc -l`
  :::

-----

## 8. よくあるエラーと対処 / Troubleshooting

|エラー / Error                          |原因 / Cause       |対処 / Fix                          |
|-------------------------------------|-----------------|----------------------------------|
|`SAindex not found`                  |インデックス未完成        |Step 2 を再実行。ログを確認                 |
|`FASTQ files not found`              |パスかファイル名の誤り      |`ls ${RAW_FASTQ_DIR}` で確認         |
|`fastp failed`                       |メモリ不足 or 破損ファイル  |`md5sum` でファイル整合性を確認              |
|`No valid paired-end files found`    |命名規則が `_1/_2` でない|スクリプト内のパターンを変更                    |
|STAR: `genome files are inconsistent`|インデックスが壊れている     |インデックスを削除して再構築                    |
|Salmon: `index not found`            |インデックスパスの誤り      |`ls ${SALMON_INDEX_DIR}/info.json`|

-----

*Last updated: 2026-04-28*