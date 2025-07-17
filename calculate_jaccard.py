#!/usr/bin/env python3

import numpy as np
import nibabel as nib
import sys

def calculate_jaccard_index(mask1, mask2):
    """Compute Jaccard Index (Intersection over Union)"""
    if not ((mask1 == 0) | (mask1 == 1)).all() or not ((mask2 == 0) | (mask2 == 1)).all():
        raise ValueError("Masks must be binary (contain only 0s and 1s).")
    
    intersection = np.logical_and(mask1, mask2).sum()
    union = np.logical_or(mask1, mask2).sum()
    
    if union == 0:
        return 0.0
    
    return intersection / union

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: calculate_jaccard.py mask1.nii.gz mask2.nii.gz")
        sys.exit(1)
    
    mask1_img = nib.load(sys.argv[1])
    mask2_img = nib.load(sys.argv[2])

    mask1 = (mask1_img.get_fdata() > 0).astype(np.uint8)
    mask2 = (mask2_img.get_fdata() > 0).astype(np.uint8)

    jaccard = calculate_jaccard_index(mask1, mask2)
    print(f"{jaccard:.6f}")