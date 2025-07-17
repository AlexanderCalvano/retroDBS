#!/bin/bash

if [[ "$1" == "-h" || "$1" == "--help" || $# -eq 0 ]]; then
  echo ""
  echo "Usage: calc_dice mask1.nii.gz mask2.niigz"
  echo ""
  echo "Where mask1 and mask2 do only contain 0 or 1."
  echo "If other values are present results will likely"
  echo "be wrong since no checks are done."
  echo ""
  exit 0
fi

sumfile=$(mktemp)
fslmaths $1 -add $2 $sumfile
sumintersect=$(fslstats $sumfile -H 3 0 2|sed -n 3p)
sumniftione=$(fslstats $1 -H 2 0 1|sed -n 2p)
sumniftitwo=$(fslstats $2 -H 2 0 1|sed -n 2p)
rm $sumfile

echo $(echo "(2*$sumintersect) / ($sumniftione + $sumniftitwo)"|bc -l)