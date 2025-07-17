#!/bin/bash
#
# PD25_metrics.sh - Calculate spatial metrics between VATs and MAS segmentations
#

# Exit on error
set -e

# Function to check dependencies
check_dependencies() {
    local deps=("fslmaths" "flirt" "python3" "bc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' not found"
            exit 1
        fi
    done
}

# Function to check if required scripts exist
check_scripts() {
    local scripts=("$DICE_SCRIPT" "$JACCARD_SCRIPT" "$HAUSDORFF_SCRIPT")
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            echo "Error: Required script not found: $script"
            exit 1
        fi
    done
}

# Function to check if VATs are available for a subject
check_vat_availability() {
    local subject_id="$1"
    local subject_vat_dir="$VAT_DIR/$subject_id"
    local vat_left="$subject_vat_dir/vat_left_in_MNI.nii.gz"
    local vat_right="$subject_vat_dir/vat_right_in_MNI.nii.gz"

    # Return true (0) if at least one VAT is available
    [ -f "$vat_left" ] || [ -f "$vat_right" ]
}

# Function to process a single subject and side
process_subject_side() {
    local subject_id="$1"
    local side="$2"
    local segmentation="$3"
    local temp_dir="$4"
    local label
    local vat_orig

    if [ "$side" == "left" ]; then
        label=3
        vat_orig="$SUBJECT_VAT_DIR/vat_left_in_MNI.nii.gz"
    else
        label=4
        vat_orig="$SUBJECT_VAT_DIR/vat_right_in_MNI.nii.gz"
    fi

    if [ ! -f "$vat_orig" ]; then
        return 0  # Skip silently if VAT is not available
    fi

    local stn_bin="$temp_dir/${subject_id}_STN_${side}_bin.nii.gz"
    local vat_resampled="$temp_dir/${subject_id}_VAT_${side}_resampled.nii.gz"
    local vat_bin="$temp_dir/${subject_id}_VAT_${side}_resampled_bin.nii.gz"

    # Extract STN
    fslmaths "$segmentation" -thr $label -uthr $label -bin "$stn_bin" || {
        echo "ERROR: Failed to extract STN for $subject_id $side" >&2
        return 1
    }

    # Resample VAT
    flirt -in "$vat_orig" -ref "$segmentation" -applyxfm -usesqform -out "$vat_resampled" -interp nearestneighbour || {
        echo "ERROR: Failed to resample VAT for $subject_id $side" >&2
        return 1
    }

    # Binarize VAT
    fslmaths "$vat_resampled" -bin "$vat_bin"

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
SEGMENTATION_DIR="$BASE_DIR/segmentationPD25"
VAT_DIR="$BASE_DIR/VATfinal"
DICE_SCRIPT="./metrics/calculate_dice.sh"
JACCARD_SCRIPT="./metrics/calculate_jaccard.py"
HAUSDORFF_SCRIPT="./metrics/calculate_hausdorff.py"
OUTPUT_CSV="$BASE_DIR/Dice_Jaccard_Hausdorff_Centroid_PD25_all_subjects.csv"
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

# Get total number of subjects for progress tracking
total_subjects=53
processed=0
skipped=0

# Process subjects
for i in $(seq 1 $total_subjects); do
    subject_id="subj$i"
    echo "-----------------------------"
    echo "Processing $subject_id... ($(( processed * 100 / total_subjects ))%)"

    # Skip if no VATs available
    if ! check_vat_availability "$subject_id"; then
        echo "Skipping $subject_id: No VATs available"
        skipped=$((skipped + 1))
        processed=$((processed + 1))
        continue
    fi

    subj_num="${subject_id//[!0-9]/}"
    segmentation="$SEGMENTATION_DIR/Warped_Sub-${subj_num}-nuclei-seg.nii.gz"
    SUBJECT_VAT_DIR="$VAT_DIR/$subject_id"

    if [ ! -f "$segmentation" ]; then
        echo "Skipping $subject_id: No segmentation file available"
        skipped=$((skipped + 1))
        processed=$((processed + 1))
        continue
    fi

    if [ "$PARALLEL" = true ]; then
        # Process both sides in parallel
        process_subject_side "$subject_id" "left" "$segmentation" "$TEMP_DIR" &
        process_subject_side "$subject_id" "right" "$segmentation" "$TEMP_DIR" &
        wait
    else
        # Process sequentially
        for side in left right; do
            process_subject_side "$subject_id" "$side" "$segmentation" "$TEMP_DIR"
        done
    fi

    processed=$((processed + 1))
done

echo "Analysis complete. Results saved to: $OUTPUT_CSV"
echo "Total subjects processed: $processed"
echo "Subjects skipped: $skipped"