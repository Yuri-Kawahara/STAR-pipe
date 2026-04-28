#!/bin/bash

###############################################################################
# サンプルリスト作成スクリプト (自動ペアリング＆サイレント重複チェック版)
# 
# 用途: FASTQファイルのディレクトリをスキャンして、ペアエンドRNA-seq
#       サンプルの一覧を作成し、ジョブアレイ用のテキストファイルを生成
#
# 使用方法:
#   bash create_sample_list.sh
#
# 出力:
#   samples_202604 - 各サンプルIDが1行ずつ記載されたファイル
#   (※重複が発生した場合は duplicate_warning.log がサイレントに生成されます)
###############################################################################

### --- 設定項目 ---
# フルパスでの参照
# 例: /Users/username/data/fastq
FASTQ_DIR="/Users/your_username/path/to/fastq"

# 出力するサンプルリストファイル
OUTPUT_LIST="samples_202604"

### --- スクリプト本体 ---
echo "======================================================"
echo "Creating sample list from FASTQ directory"
echo "======================================================"
echo "FASTQ directory: ${FASTQ_DIR}"
echo "Output list: ${OUTPUT_LIST}"
echo ""

# ディレクトリの存在確認
if [ ! -d "${FASTQ_DIR}" ]; then
    echo "ERROR: FASTQ directory not found: ${FASTQ_DIR}"
    exit 1
fi

# 一時ファイル
TEMP_LIST=$(mktemp)

echo "Scanning for FASTQ files and auto-detecting pairs..."

# Mac(Bash 3.2)でも動くように、find結果をソートして配列に格納
files=()
while IFS= read -r line; do
    files+=("$line")
done < <(find "${FASTQ_DIR}" -maxdepth 1 -type f -exec basename {} \; | sort)

# 隣接するファイルを比較して「1」と「2」の1文字違いを自動検出
for (( i=0; i<${#files[@]}-1; i++ )); do
    f1="${files[$i]}"
    f2="${files[$i+1]}"
    
    # 文字列の長さが同じ場合のみ比較
    if [[ ${#f1} -eq ${#f2} ]]; then
        diff_count=0
        diff_index=-1
        
        # 1文字ずつ比較
        for (( j=0; j<${#f1}; j++ )); do
            c1="${f1:$j:1}"
            c2="${f2:$j:1}"
            
            if [[ "$c1" != "$c2" ]]; then
                # 違いが '1' と '2' かどうか判定
                if [[ "$c1" == "1" && "$c2" == "2" ]]; then
                    diff_count=$((diff_count+1))
                    diff_index=$j
                else
                    # 1と2以外の違いが見つかった場合はペアとみなさない
                    diff_count=99 
                    break
                fi
            fi
        done
        
        # 正確に1箇所だけ「1」と「2」の違いがある場合
        if [[ $diff_count -eq 1 ]]; then
            # サンプルIDの抽出: 異なる文字（1と2）の直前までの文字列を取得
            prefix="${f1:0:$diff_index}"
            
            # 末尾に残った識別子（_R, -R, _, -）を削除して綺麗なサンプルIDにする
            sample_id=$(echo "$prefix" | sed 's/_R*$//; s/-R*$//; s/_$//; s/-$//')
            
            echo "$sample_id" >> "$TEMP_LIST"
            echo "  Found pair: $f1 & $f2 -> ID: ${sample_id}"
            
            # f2は既にペアとして処理されたので次のループをスキップする
            ((i++))
            continue
        fi
    fi
done

# 結果が空でないか確認
if [ ! -s "$TEMP_LIST" ]; then
    echo ""
    echo "ERROR: No valid paired-end FASTQ files found!"
    echo "Please check if FASTQ directory contains pair files with '1' and '2' character differences."
    rm -f "$TEMP_LIST"
    exit 1
fi

# --- 追加部分: サイレントな重複チェック ---
# sortとuniq -dコマンドを組み合わせて、複数回出現するサンプルIDのみを抽出します。
# 変数に格納することで画面出力を抑制し、値が存在する場合のみログに書き出します。
DUPLICATES=$(sort "$TEMP_LIST" | uniq -d)

if [ -n "$DUPLICATES" ]; then
    # 画面には出力せず、警告ログファイルを作成
    echo "WARNING: Duplicate sample IDs detected in the extraction process." > duplicate_warning.log
    echo "This may indicate irregular file naming." >> duplicate_warning.log
    echo "---------------------------------------------------------------" >> duplicate_warning.log
    echo "$DUPLICATES" >> duplicate_warning.log
fi
# ----------------------------------------

# ソートしてユニークにし、最終ファイルに出力
sort -u "$TEMP_LIST" > "$OUTPUT_LIST"
rm -f "$TEMP_LIST"

# 結果サマリー (Macのwcコマンドによる不要な空白出力をawkで除去)
NUM_SAMPLES=$(wc -l < "$OUTPUT_LIST" | awk '{print $1}')

echo ""
echo "======================================================"
echo "Sample list created successfully!"
echo "======================================================"
echo "Total samples: ${NUM_SAMPLES}"
echo "Output file: ${OUTPUT_LIST}"
echo ""
echo "First 10 samples:"
head -10 "$OUTPUT_LIST"

if [ $NUM_SAMPLES -gt 10 ]; then
    echo "..."
    echo "(showing first 10 of ${NUM_SAMPLES} samples)"
fi

echo ""
echo "======================================================"
echo "Next steps:"
echo "======================================================"
echo "1. Review the sample list:"
echo "   cat ${OUTPUT_LIST}"
echo ""
echo "2. Submit the job array:"
echo "   qsub -t 1-${NUM_SAMPLES} fastq_pipe.sh"
echo ""
echo "   Or specify a range (e.g., first 10 samples):"
echo "   qsub -t 1-10 fastq_pipe.sh"
echo "======================================================"
