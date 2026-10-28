#!/bin/bash
# Reproduces the whole lab run. Output goes to out\. Run from the lab folder.
cd "$(dirname "$0")"; E=./engine/drag-lint.exe; mkdir -p db out
$E index --project CycleLab.dproj --db db/CycleLab.sqlite > out/01-index.txt 2>&1
$E index --project illegal/IllegalLab.dproj --db db/IllegalLab.sqlite > out/01-index-illegal.txt 2>&1
$E cycles --db db/CycleLab.sqlite --edges > out/02-cycles-before.txt 2>&1
$E cycles --db db/IllegalLab.sqlite --edges --f2047 > out/02-f2047-illegal.txt 2>&1
$E cycles --db db/CycleLab.sqlite --edges --causes --plan --project CycleLab.dproj > out/03-plan-before.txt 2>&1
for u in labvarwidget demologger demouiconnect labdira labguarda democontrolplan labctorowner labrchost labinitsink labexchost labclswidget; do
  timeout 400 $E cycles --db db/CycleLab.sqlite --fix --project CycleLab.dproj --unit $u > out/04-dry-$u.txt 2>&1; echo "$u exit=$?" >> out/04-summary.txt
done
for u in demologger demouiconnect democontrolplan labinitsink labexchost; do
  timeout 400 $E cycles --db db/CycleLab.sqlite --fix --project CycleLab.dproj --unit $u --apply > out/05-apply-$u.txt 2>&1; echo "$u exit=$?" >> out/05-summary.txt
done
for u in LabDirA LabGuardA LabCtorOwner LabRcHost LabVarHost LabClsRegistry; do
  $E uses-fix $u.pas --project CycleLab.dproj --db db/CycleLab.sqlite --remove-unused > out/06-usesfix-dry-$u.txt 2>&1
done
$E uses-fix LabDirA.pas --project CycleLab.dproj --db db/CycleLab.sqlite --remove-unused --apply > out/07-usesfix-apply-LabDirA.txt 2>&1
$E index --project CycleLab.dproj --db db/CycleLab.sqlite > out/08-index-after.txt 2>&1
$E cycles --db db/CycleLab.sqlite --edges > out/09-cycles-after.txt 2>&1
$E cycles --db db/CycleLab.sqlite --edges --causes --plan --project CycleLab.dproj > out/10-plan-after.txt 2>&1
echo ALLDONE >> out/05-summary.txt
