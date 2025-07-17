#!/bin/bash
#
# transform_VAT.sh - Script to transform VAT files to MNI space using ANTs
#

EXTERNAL_ROOT="./data/VTA"  
PD25="./data/segmentationPD25"  
LOCAL_OUT="./output/VATfinal"  

for SUBJ_PATH in "${EXTERNAL_ROOT}"/subj*; do
    SUBJ=$(basename "$SUBJ_PATH")     
    SUBJ_NUM=${SUBJ#subj}             
    echo "Processing $SUBJ"

    # Check for VAT directory
    VAT_DIRS=("retroDBS" "retroDBS2.0" "retroDBS3.0")
    VAT_BASE=""
    for DIR in "${VAT_DIRS[@]}"; do
        PATH_CHECK="${SUBJ_PATH}/stimulations/MNI_ICBM_2009b_NLIN_ASYM/${DIR}"
        if [[ -d "$PATH_CHECK" ]]; then
            VAT_BASE="$PATH_CHECK"
            break
        fi
    done

    if [[ -z "$VAT_BASE" ]]; then
        echo "  No VAT directory found for $SUBJ"
        continue
    fi

    # local output folder
    LOCAL_SUBJ_OUT="${LOCAL_OUT}/${SUBJ}"
    mkdir -p "$LOCAL_SUBJ_OUT"

    # select warped image from previous step
    REF_MNI="${PD25}/Sub-${SUBJ_NUM}_PD25_2MNI_Warped.nii.gz"
    if [[ ! -f "$REF_MNI" ]]; then
        echo "  Reference MNI image not found for $SUBJ — skipping."
        continue
    fi

    # process each VAT side seperately 
    for SIDE in left right; do
        SRC_VAT="${VAT_BASE}/vat_${SIDE}.nii"
        LOCAL_VAT="${LOCAL_SUBJ_OUT}/vat_${SIDE}.nii"
        OUTPUT="${LOCAL_SUBJ_OUT}/vat_${SIDE}_in_MNI.nii.gz"

        if [[ -f "$SRC_VAT" ]]; then
            echo "  Copying and resampling ${SIDE} VAT..."
            cp "$SRC_VAT" "$LOCAL_VAT"

            antsApplyTransforms \
              -d 3 \
              -i "$LOCAL_VAT" \
              -r "$REF_MNI" \
              -n NearestNeighbor \
              -t identity \
              -o "$OUTPUT"
        else
            echo "  VAT ($SIDE) not found for $SUBJ"
        fi
    done
done

echo "All VATs copied and resampled to MNI."