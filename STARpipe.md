# STAR Parameters Guide

### Based on GDC/TCGA pipeline · Explained with STAR manual

> **ベース / Source**  
> [GDC mRNA Analysis Pipeline (DR32)](https://docs.gdc.cancer.gov/Data/Bioinformatics_Pipelines/Expression_mRNA_Pipeline/)  
> [STAR manual 2.7.11b](https://github.com/alexdobin/STAR/blob/master/doc/STARmanual.pdf)

-----

## 現在の設定 / Current command

```bash
STAR \
  --runThreadN ${RUN_THREADS} \
  --genomeDir ${ACTIVE_INDEX} \
  --sjdbGTFfile ${ACTIVE_GTF} \
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
```

-----

## パラメータ解説 / Parameter reference

-----

### `--twopassMode Basic`

1回目でスプライスジャンクションを検出し、2回目のアライメントに活用する。  
Detects splice junctions in pass 1, uses them to improve alignment in pass 2.

> STAR manual: *“New option to activate on the fly ‘per sample’ 2-pass method”*

-----

### `--outFilterMultimapNmax 20`

1リードが何箇所にマップされることを許すか。超えたリードは unmapped 扱い。  
Max loci a read can map to; reads exceeding this are considered unmapped.

> STAR manual (ENCODE options): *“max number of multiple alignments allowed for a read: if exceeded, the read is considered unmapped”*

|      |                                |
|------|--------------------------------|
|Up →  |より多くのリピート領域・偽遺伝子リードを拾う。発現定量のノイズ増|
|Down →|ユニークマップのみに近づく。融合遺伝子検出感度が下がる     |

-----

### `--alignSJDBoverhangMin 1`

**アノテーション済み**スプライスジャンクションのオーバーハング最小長。  
Min overhang required for *annotated* splice junctions.

> STAR manual (ENCODE options): *“minimum overhang for annotated junctions”*

|      |                    |
|------|--------------------|
|Up →  |既知ジャンクションへのマップが厳しくなる|
|Down →|1が最小値（最大感度）         |

-----

### `--outFilterMismatchNmax 10`

リードペアあたりの許容ミスマッチ塩基数の上限（絶対値）。  
Max number of mismatches per read pair (absolute).

> STAR manual (ENCODE options): *“maximum number of mismatches per pair, large number switches off this filter”*

> GDC は `999`（実質OFF）にして `--outFilterMismatchNoverLmax 0.1` で相対制御する方式を採用。  
> 絶対値で制御したい場合はこのパラメータを使う。

|      |                                 |
|------|---------------------------------|
|Up →  |ミスマッチの多いリードも通過。低品質サンプルや異種間マッピング向き|
|Down →|厳密になる。高品質サンプルや SNV 解析向き          |

-----

### `--alignIntronMax 300000`

イントロンの最大長 (bp)。これを超えるスプライシングは無視される。  
Max intron size in bp.

> STAR manual (ENCODE options): *“maximum intron length”*

> GDC (ヒト/マウス標準) は `1000000`。ヒトには長いイントロン（～500kb）が存在するため、`300000` では見逃す可能性がある。

|      |                                   |
|------|-----------------------------------|
|Up →  |長いイントロンを持つ遺伝子をカバー。ヒトには `1000000` 推奨|
|Down →|短いイントロンの生物種（線虫等）向き。誤マッピング減         |

-----

### `--alignMatesGapMax 300000`

ペアエンドの2本のリード間の最大ゲノム距離 (bp)。  
Max genomic distance between paired-end mates.

> STAR manual (ENCODE options): *“maximum genomic distance between mates”*

> `alignIntronMax` と同じ値にするのが基本。GDC は両方 `1000000`。

|      |                          |
|------|--------------------------|
|Up →  |遠く離れたペアも許容。ロングインサートライブラリ向き|
|Down →|近接ペアのみ許容。誤マッピング減          |

-----

### `--sjdbScore 2`

スプライスジャンクションを跨ぐアライメントへのボーナススコア。  
Bonus alignment score for reads crossing splice junctions.

> GDC (ICGC 方式) で採用。STAR デフォルトも `2`。

|      |                      |
|------|----------------------|
|Up →  |ジャンクション跨ぎリードが優先されやすくなる|
|Down →|ジャンクション優先度が下がる        |

-----

### `--genomeLoad NoSharedMemory`

ゲノムをプロセス間で共有しない。  
Don’t share genome in memory across processes.

> STAR manual: *“By default, genomeLoad NoSharedMemory, shared memory is not used.”*

> HPC ジョブアレイでは `NoSharedMemory` が安全。`LoadAndKeep` にすると複数ジョブで共有できるが環境依存のトラブルが多い。

-----

### `--outFilterMatchNminOverLread 0.33`

マッチ塩基数 / リード長 の最小比率。  
Min ratio of matched bases to read length.

> GDC・ENCODE・ICGC 全パイプラインが `0.33` を採用。STAR デフォルトは `0.66`。

|      |                             |
|------|-----------------------------|
|Up →  |より厳密。短いリードや末端品質が低いリードが落ちやすくなる|
|Down →|より緩く。低品質リードもマップされやすい         |

-----

### `--outFilterScoreMinOverLread 0.33`

アライメントスコア / リード長 の最小比率。  
Min ratio of alignment score to read length.

> `outFilterMatchNminOverLread` と対になるパラメータ。同じ値にするのが標準。

|      |                  |
|------|------------------|
|Up →  |スコアの低いアライメントが除去される|
|Down →|低スコアアライメントも通過     |

-----

### `--outSAMtype BAM SortedByCoordinate`

ゲノム座標でソートされた BAM を出力する。  
Output coordinate-sorted BAM.

> STAR manual: *“output sorted by coordinate Aligned.sortedByCoord.out.bam file, similar to samtools sort command”*

> IGV・featureCounts・tximport すべてに必要。変更不要。

-----

### `--outSAMunmapped Within`

マップされなかったリードも BAM ファイルに含める。  
Keep unmapped reads inside the BAM.

> STAR manual: *“outSAMunmapped Within option”*

> QC・デバッグに有用。削除するとBAMサイズが小さくなる。

-----

### `--outSAMattributes Standard`

標準 SAM タグ（NH HI NM MD AS）を付与する。  
Add standard SAM tags.

> featureCounts・GATK 等の下流ツールはこれらのタグを期待する。変更不要。

-----

### `--quantMode GeneCounts`

遺伝子ごとのリードカウントを `ReadsPerGene.out.tab` に出力する。  
Output per-gene read counts to `ReadsPerGene.out.tab`.

> STAR manual: *“count reads per gene”*

出力される3列:

|列   |内容              |
|----|----------------|
|col2|Unstranded      |
|col3|Stranded (sense)|
|col4|Antisense       |


> DESeq2・edgeR に直接渡せる。どの列を使うかはライブラリのストランド設定に依存。

-----

### `--chimSegmentMin 15`

キメラアライメントのメインセグメントの最小長 (bp)。`0` にすると chimeric 出力が無効。  
Min length of chimeric segment. Set to `0` to disable chimeric output entirely.

> STAR manual: *“minimum length of chimeric segment length; if 0, no chimeric output”*

|      |                      |
|------|----------------------|
|Up →  |より確信度の高い融合遺伝子のみ検出。偽陽性減|
|Down →|短いセグメントも拾う。感度上がるが偽陽性増 |


> **融合遺伝子解析が不要なら、`chimSegmentMin` 以下の chim 系5パラメータをまとめて削除するとランタイムが短くなる。**

-----

### `--chimJunctionOverhangMin 15`

キメラジャンクションのオーバーハング最小長 (bp)。  
Min overhang for chimeric junction.

> GDC 標準。`chimSegmentMin` と同じ値にするのが基本。

|      |            |
|------|------------|
|Up →  |より厳密な融合遺伝子検出|
|Down →|感度上がるが偽陽性増  |

-----

### `--chimOutType Junctions WithinBAM SoftClip`

キメラリードの出力形式。  
Output format for chimeric reads.

> STAR manual: *“in addition to chimeric junction information, output chimeric alignments with soft-clipping into main genomic BAM file”*

> `Junctions` → `Chimeric.out.junction` ファイルを出力（STAR-Fusion の入力）  
> `WithinBAM SoftClip` → 通常の BAM にも chimeric reads を含める

-----

### `--chimMainSegmentMultNmax 1`

キメラのメインセグメントの最大マルチマップ数。  
Max multimapping for the main segment of a chimeric read.

> `1` = メインセグメントがユニークにマップされたものだけ chimeric 候補にする。偽陽性を抑える。変更不要。

-----

### `--chimOutJunctionFormat 1`

Junction ファイルの出力形式。STAR-Fusion が要求する形式。  
Junction output format required by STAR-Fusion. 変更不要。

-----

## 参照 / References

- GDC mRNA Analysis Pipeline: https://docs.gdc.cancer.gov/Data/Bioinformatics_Pipelines/Expression_mRNA_Pipeline/
- STAR manual 2.7.11b: https://github.com/alexdobin/STAR/blob/master/doc/STARmanual.pdf

-----

*Last updated: 2026-04-29*