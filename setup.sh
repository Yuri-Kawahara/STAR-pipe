#!/bin/bash

# 1. Conda(Miniconda)がインストールされているか確認
if ! command -v conda &> /dev/null; then
    echo "Condaが見つかりません。先にMinicondaをインストールしてください。"
    exit 1
fi

# 2. 解析用の新しい環境を作成 (名前は 'bio_tools')
# bioconda チャンネルから一括インストール
echo "解析環境を作成し、ツールをインストールします..."
conda create -n bio_tools -c bioconda -c conda-forge \
    fastqc \
    fastp \
    star -y

echo "インストールが完了しました。"
echo "以下のコマンドでツールを使用可能になります:"
echo "conda activate bio_tools"
