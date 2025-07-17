#!/bin/bash
#
# preop_metrics.sh - Calculate spatial metrics between VATs and BLE segmentations
#

# Exit on error
set -e

# check dependencies
check_dependencies() {
    local deps=("fslmaths" "flirt" "python3" "bc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' not found"
            exit 1
        fi
    done
}

# Check if required scripts exist
check_scripts() {
    local scripts=("$DICE_SCRIPT" "$JACCARD_SCRIPT" "$HAUSDORFF_SCRIPT")
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            echo "Error: Required script not found: $script"
            exit 1
        fi
    done
}

# check if preop STN and VATs are available for a subject
check_availability() {
    local subject_id="$1"
    local subject_vat_dir="$VAT_DIR/$subject_id"
    local subject_seg_dir="$SEGMENTATION_DIR/$subject_id/transformed"
    local stn_left="$subject_seg_dir/${subject_id}_STN_left_in_MNI.nii.gz"
    local stn_right="$subject_seg_dir/${subject_id}_STN_right_in_MNI.nii.gz"
    local vat_left="$subject_vat_dir/vat_left_in_MNI.nii.gz"
    local vat_right="$subject_vat_dir/vat_right_in_MNI.nii.gz"

    # Return true (0) if at least one pair of STN and VAT is available
    { [ -f "$stn_left" ] && [ -f "$vat_left" ]; } || { [ -f "$stn_right" ] && [ -f "$vat_right" ]; }
}

# Process a single subject and side
process_subject_side() {
    local subject_id="$1"
    local side="$2"
    local temp_dir="$3"
    
    local subject_vat_dir="$VAT_DIR/$subject_id"
    local subject_seg_dir="$SEGMENTATION_DIR/$subject_id/transformed"
    local stn_orig="$subject_seg_dir/${subject_id}_STN_${side}_in_MNI.nii.gz"
    local vat_orig="$subject_vat_dir/vat_${side}_in_MNI.nii.gz"

    if [ ! -f "$stn_orig" ] || [ ! -f "$vat_orig" ]; then
        return 0  
    fi

    local stn_bin="$temp_dir/${subject_id}_STN_${side}_bin.nii.gz"
    local vat_bin="$temp_dir/${subject_id}_VAT_${side}_bin.nii.gz"

    # Binarize STN and VAT
    fslmaths "$stn_orig" -bin "$stn_bin" || {
        echo "ERROR: Failed to binarize STN for $subject_id $side" >&2
        return 1
    }

    fslmaths "$vat_orig" -bin "$vat_bin" || {
        echo "ERROR: Failed to binarize VAT for $subject_id $side" >&2
        return 1
    }

    # Calculate metrics
    local dice jaccard hd avg_hd hd95 centroid_dist
    dice=$($DICE_SCRIPT "$vat_bin" "$stn_bin")
    jaccard=$(python3 "$JACCARD_SCRIPT" "$vat_bin" "$stn_bin")
    read -r hd avg_hd hd95 <<< $(python3 "$HAUSDORFF_SCRIPT" "$vat_bin" "$stn_bin")

    # Calculate centroid distance
    local centroid_vat=($(fslstats "$vat_bin" -c))
    local centroid_stn=($(fslstats "$stn_bin" -c))

    if [ ${#centroid_vat[@]} -eq 3 ] && [ ${#centroid_stn[@]} -eq 3 ]; then
        local dx dy dz
        dx=$(echo "${centroid_vat[0]} - ${centroid_stn[0]}" | bc -l)
        dy=$(echo "${centroid_vat[1]} - ${centroid_stn[1]}" | bc -l)
        dz=$(echo "${centroid_vat[2]} - ${centroid_stn[2]}" | bc -l)
        centroid_dist=$(echo "scale=6; sqrt($dx^2 + $dy^2 + $dz^2)" | bc -l)
    else
        centroid_dist="NaN"
    fi

    # Output results
    printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
        "$subject_id" "$side" "$dice" "$jaccard" "$hd" "$avg_hd" "$hd95" "$centroid_dist" >> "$OUTPUT_CSV"
    
    echo "→ $side: Dice = $dice | Jaccard = $jaccard | HD = $hd | Avg = $avg_hd | HD95 = $hd95 | Centroid = $centroid_dist"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base-dir)
            BASE_DIR="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default paths if not provided
BASE_DIR="${BASE_DIR:-./data}"
SEGMENTATION_DIR="$BASE_DIR/preoperative_planningNIFTI"
VAT_DIR="$BASE_DIR/VATfinal"
DICE_SCRIPT="./metrics/calculate_dice.sh"
JACCARD_SCRIPT="./metrics/calculate_jaccard.py"
HAUSDORFF_SCRIPT="./metrics/calculate_hausdorff.py"
OUTPUT_CSV="$BASE_DIR/Dice_Jaccard_Hausdorff_Centroid_preopSTN_all_subjects.csv"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check dependencies and scripts
check_dependencies
check_scripts

# Validate directories
for dir in "$BASE_DIR" "$SEGMENTATION_DIR" "$VAT_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "Error: Directory not found: $dir"
        exit 1
    fi
done

# Initialize output CSV
echo "Subject,Side,Dice,Jaccard,Hausdorff,AverageHausdorff,HD95,CentroidDistance" > "$OUTPUT_CSV"

declare -a skipped_subjects

total_subjects=53
processed=0

# Process all subjects
for i in $(seq 1 $total_subjects); do
    subject_id="subj$i"
    echo "-----------------------------"
    echo "Processing $subject_id... ($(( processed * 100 / total_subjects ))%)"

    # Skip if no STN or VATs available
    if ! check_availability "$subject_id"; then
        echo "Skipping $subject_id: No matching STN-VAT pairs available"
        skipped_subjects+=("$subject_id")
        processed=$((processed + 1))
        continue
    fi

    if [ "$PARALLEL" = true ]; then
        process_subject_side "$subject_id" "left" "$TEMP_DIR" &
        process_subject_side "$subject_id" "right" "$TEMP_DIR" &
        wait
    else
        for side in left right; do
            process_subject_side "$subject_id" "$side" "$TEMP_DIR"
        done
    fi

    processed=$((processed + 1))
done

echo "DONE!Results saved to: $OUTPUT_CSV"
echo "Total subjects processed: $processed"
echo "Subjects skipped: ${#skipped_subjects[@]}"
if [ ${#skipped_subjects[@]} -gt 0 ]; then
    echo "Skipped subjects:"
    printf '  %s\n' "${skipped_subjects[@]}"
fi