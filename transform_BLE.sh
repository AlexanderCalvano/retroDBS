#!/bin/bash
#
# transform_preopSTN.sh - Script to transform preoperative STN masks to MNI space
#

ROOT="./data"
PREOP="${ROOT}/preoperative_planningNIFTI"
PD25="${ROOT}/segmentationPD25"

SUBJECTS=($(basename -a "$PREOP"/subj*))

# Create identity matrix to align Brainlab-STN with native T1
IDENTITY="${ROOT}/identity.mat"
echo -e "1 0 0 0\n0 1 0 0\n0 0 1 0\n0 0 0 1" > "$IDENTITY"

process_stn_mask() {
    local SUBJ=$1
    local SIDE=$2
    local INPUT_MASK=$3

    local T1_NATIVE="${PREOP}/${SUBJ}/${SUBJ}_.nii"
    local AFFINE_MAT="${PD25}/Sub-${SUBJ#subj}-T1nav-N4brain-icbm.mat"
    local MNI_REF="${PD25}/Sub-${SUBJ#subj}_PD25_2MNI_Warped.nii.gz"
    local OUTDIR="${PREOP}/${SUBJ}/transformed"
    mkdir -p "$OUTDIR"

    local OUTNAME_T1="${SUBJ}_STN_${SIDE}_in_T1"
    local OUTNAME_MNI="${SUBJ}_STN_${SIDE}_in_MNI"

    echo "-------- Processing ${SUBJ} | ${SIDE} STN --------"
    echo "Input: $INPUT_MASK"

    # create tmp files
    local STN_TMP="${OUTDIR}/${SUBJ}_${SIDE}_stn_tmp.nii.gz"
    local T1_TMP="${OUTDIR}/${SUBJ}_${SIDE}_t1_tmp.nii.gz"

    cp "$INPUT_MASK" "$STN_TMP"
    cp "$T1_NATIVE" "$T1_TMP"

    fslreorient2std "$STN_TMP" "$STN_TMP"
    fslreorient2std "$T1_TMP" "$T1_TMP"

    # Reslice STN to T1 orientation
    flirt -in "$STN_TMP" \
          -ref "$T1_TMP" \
          -applyxfm \
          -init "$IDENTITY" \
          -interp nearestneighbour \
          -out "${OUTDIR}/${OUTNAME_T1}.nii.gz"

    # Apply affine transform to MNI
    flirt -in "${OUTDIR}/${OUTNAME_T1}.nii.gz" \
          -ref "$MNI_REF" \
          -applyxfm \
          -init "$AFFINE_MAT" \
          -interp nearestneighbour \
          -out "${OUTDIR}/${OUTNAME_MNI}.nii.gz"
}

for SUBJ in "${SUBJECTS[@]}"; do
    SUBJECT_SEG_DIR="${PREOP}/${SUBJ}"
    SUBJECT_ID="$SUBJ"

    STN_LEFT=$(find "$SUBJECT_SEG_DIR" -type f -name "${SUBJECT_ID}_BURNED-IN_Subthalamic_Nucleus_Left*.nii*" | head -n 1)
    STN_RIGHT=$(find "$SUBJECT_SEG_DIR" -type f -name "${SUBJECT_ID}_BURNED-IN_Subthalamic_Nucleus_Right*.nii*" | head -n 1)

    if [[ -f "$STN_LEFT" && -f "$STN_RIGHT" ]]; then
        process_stn_mask "$SUBJ" "left" "$STN_LEFT"
        process_stn_mask "$SUBJ" "right" "$STN_RIGHT"
    else
        echo "Missing STN mask(s) for $SUBJ:"
        [[ ! -f "$STN_LEFT" ]] && echo "  Left mask not found"
        [[ ! -f "$STN_RIGHT" ]] && echo "  Right mask not found"
    fi
done

echo "Brainlab-STN to MNI done."