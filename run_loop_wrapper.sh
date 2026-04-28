#!/bin/bash

# 使用方法: bash run_loop_wrapper.sh <サンプルリストのパス> <実行するスクリプトのパス>
# 例: bash run_loop_wrapper.sh samples_202604 fastq_pipe_unified.sh

LIST_FILE=$1
SCRIPT_FILE=$2

if [ -z "${LIST_FILE}" ] || [ -z "${SCRIPT_FILE}" ]; then
    echo "使用方法: bash run_loop_wrapper.sh <サンプルリスト> <実行スクリプト>"
    exit 1
fi

if [ ! -f "${LIST_FILE}" ]; then
    echo "エラー: リストファイルが見つかりません - ${LIST_FILE}"
    exit 1
fi

if [ ! -f "${SCRIPT_FILE}" ]; then
    echo "エラー: 実行スクリプトが見つかりません - ${SCRIPT_FILE}"
    exit 1
fi

# 実行権限を付与
chmod +x "${SCRIPT_FILE}"

echo "======================================================"
echo "ループ処理を開始します"
echo "対象リスト: ${LIST_FILE}"
echo "実行スクリプト: ${SCRIPT_FILE}"
echo "======================================================"

TOTAL=$(wc -l < "${LIST_FILE}" | awk '{print $1}')
COUNT=1

# リストを1行ずつ読み込んで処理
while IFS= read -r SAMPLE_ID; do
    # 空行をスキップ
    if [ -z "${SAMPLE_ID}" ]; then continue; fi

    echo ""
    echo "[${COUNT}/${TOTAL}] サンプル処理開始: ${SAMPLE_ID}"
    
    # スクリプトに引数としてサンプルIDを渡して実行
    ./"${SCRIPT_FILE}" "${SAMPLE_ID}"

    if [ $? -ne 0 ]; then
        echo "エラー: ${SAMPLE_ID} の処理中にエラーが発生しました。ループを中断します。"
        exit 1
    fi
    
    COUNT=$((COUNT + 1))
done < "${LIST_FILE}"

echo ""
echo "======================================================"
echo "すべてのサンプルのループ処理が完了しました。"
echo "======================================================"
