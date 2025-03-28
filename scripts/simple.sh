#!/bin/bash
#pipeline for mapping EMS mutants
#bug report to Guy Wachsman gw57@duke.edu

#exec 3>&1 4>&2
#trap 'exec 2>&4 1>&3' 0 1 2 3
#exec 1>log.out 2>&1

#works with java version "23.0.1" 2024-10-15


{ # the entire script stdout and error will be displayed and redirected to log.txt
#reading variables
source ./scripts/simple_variables.sh

# #install programs bwa and samtools
# cd programs/bwa-0.7.17    ###0.7.18-r1243-dirty
# make clean 
# make  #########installed 0.7.18 in global

#Download GATK
wget -r https://github.com/broadinstitute/gatk/releases/download/4.6.1.0/gatk-4.6.1.0.zip
unzip ./github.com/broadinstitute/gatk/releases/download/4.6.1.0/gatk-4.6.1.0.zip -d programs/
rm -r ./github.com

brew install bwa ####### will install globally

#new version
cd programs/samtools-1.15
make clean
./configure
make

# cd samtools-1.21    # and similarly for bcftools and htslib
# ./configure --prefix=/Users/guywachsman/Guy-work/Elo/Banana/SIMPLE/fusarium/simple2.0/programs/samtools-1.21############################################################
# make
# make install
# 

cd ../../

#downloading & creating fasta file
#fasta_link=`awk -v var="$my_species" 'match($1, var) {print $2}' ./scripts/data_base.txt`

if ! [ -f ./refs/$my_species.fa ]; then
  curl -o ./refs/$my_species.fa.gz $fasta_link
  gzip -d ./refs/$my_species.fa.gz
fi

#replacing roman numerals in numbers C. elegans############################
if [ $my_species = "caenorhabditis_elegans" ]; then
    awk '{gsub(/^[\>][I]$/, ">1", $1); gsub(/^[\>][I][I]$/, ">2", $1); gsub(/^[\>][I][I][I]$/, ">3", $1); gsub(/^[\>][I][V]$/, ">4", $1); gsub(/^[\>][V]$/, ">5", $1);print}' ./refs/$my_species.fa > ./refs/$my_species.1.fa
fi

if [ -f ./refs/$my_species.1.fa ]; then 
    mv ./refs/$my_species.1.fa ./refs/$my_species.fa
fi

#################################################### 
#################################################### 
#head -n -1 (neg value) doesn't work on mac
# awk '/[Ss]caffold/ || /[Cc]ontig/ {exit} {print}' ./refs/$my_species.fa > ./refs/$my_species.chrs.fa #########################
# #fa=./refs/$my_species.chrs.fa
#################################################### 
#################################################################



#choosing new release; 31 didn't work
#downloading & creating knownsnps file
#knownsnps_link=`awk -v var="$my_species" 'match($1, var) {print $3}' ./scripts/data_base.txt`
if ! [ -f ./refs/$my_species.vcf ]; then
  curl -o ./refs/$my_species.vcf.gz -Lk $knownsnps_link
  gzip -d ./refs/$my_species.vcf.gz
fi
#################################################################

#reference input files that are necessary to run the prograns
#knownsnps=./refs/$my_species.vcf
#ftp://ftp.ensemblgenomes.org/pub/plants/release-31/vcf/arabidopsis_thaliana/arabidopsis_thaliana.vcf.gz
#snpEffDB=$snpEff_link #paste the snpEff annotated genome name

####creating reference files####
#creating .fai file
programs/samtools-1.15/samtools faidx ./refs/$my_species.fa

#creating bwa index files
bwa index -p $my_species -a is ./refs/$my_species.fa
mv $my_species.* ./refs/

#generating dict file for GATK
$java -Xmx2g -jar programs/picard.jar CreateSequenceDictionary R=./refs/$my_species.fa O=./refs/$my_species.dict


#making sure that all ref files where loaded and/or created; this is a good control and id the output is "something went wrong", it is usually picard failing due to a problem with java
a=`ls -l refs/ | wc -l`
if [ $a = 11 ]; then
	echo "$(tput setaf 2)refs loaded properly $(tput setaf 7)"
else
	echo "$(tput setaf 1)something went wrong $(tput setaf 7)"
fi


#mapping w/ BWA
bwa mem -t 2 -M ./refs/$my_species ${mut_files[*]} > output/$mut.sam &
bwa mem -t 2 -M ./refs/$my_species ${wt_files[*]} > output/$wt.sam
wait

#due to old samtools version this step is probably necessary
programs/samtools-1.15/samtools view -bSh output/$mut.sam > output/$mut.bam &
programs/samtools-1.15/samtools view -bSh output/$wt.sam > output/$wt.bam
wait

rm -r output/*.sam

#this step is probably needed only when you have paired-end; in any case it should come before coordinate sorting (next step) on name-sorted files
programs/samtools-1.15/samtools fixmate output/$mut.bam output/$mut.fix.bam &
programs/samtools-1.15/samtools fixmate output/$wt.bam output/$wt.fix.bam
wait

#sort by coordinates
programs/samtools-1.15/samtools sort -o output/$mut.sort.bam output/$mut.fix.bam &
programs/samtools-1.15/samtools sort -o output/$wt.sort.bam output/$wt.fix.bam 
wait

$java -Xmx2g -jar programs/picard.jar MarkDuplicates I=output/$mut.sort.bam O=output/$mut.sort.md.bam METRICS_FILE=output/$mut.matrics.txt ASSUME_SORTED=true &
$java -Xmx2g -jar programs/picard.jar MarkDuplicates I=output/$wt.sort.bam O=output/$wt.sort.md.bam METRICS_FILE=output/$wt.matrics.txt ASSUME_SORTED=true
wait

#this part is just to add header for further gatk tools
$java -Xmx2g -jar programs/picard.jar AddOrReplaceReadGroups I=output/$mut.sort.md.bam O=output/$mut.sort.md.rg.bam RGLB=$mut RGPL=illumina RGSM=$mut RGPU=run1 SORT_ORDER=coordinate &
$java -Xmx2g -jar programs/picard.jar AddOrReplaceReadGroups I=output/$wt.sort.md.bam O=output/$wt.sort.md.rg.bam RGLB=$wt RGPL=illumina RGSM=$wt RGPU=run1 SORT_ORDER=coordinate
wait

$java -Xmx2g -jar programs/picard.jar BuildBamIndex INPUT=output/$mut.sort.md.rg.bam &
$java -Xmx2g -jar programs/picard.jar BuildBamIndex INPUT=output/$wt.sort.md.rg.bam
wait


#Variant calling using GATK HC extra parameters
./programs/gatk-4.6.1.0/gatk --java-options "-Xmx4g" HaplotypeCaller -R ./refs/$my_species.fa -I output/$wt.sort.md.rg.bam -I output/$mut.sort.md.rg.bam -O output/$line.hc.vcf


############prepering for R#########################
#Exclude indels from a VCF
#$java -Xmx2g -jar programs/GenomeAnalysisTK.jar -R $fa -T SelectVariants --variant output/$line.hc.vcf -o output/$line.selvars.vcf --selectTypeToInclude SNP

#now make it into a table
./programs/gatk-4.6.1.0/gatk --java-options "-Xmx4g" VariantsToTable -R ./refs/$my_species.fa -V output/$line.hc.vcf -F CHROM -F POS -F REF -F ALT -GF GT -GF AD -GF DP -GF GQ -O output/$line.table

#$java -jar programs/GenomeAnalysisTK.jar -R $fa -T VariantsToTable -V output/$line.hc.vcf -F CHROM -F POS -F REF -F ALT -GF GT -GF AD -GF DP -GF GQ -o output/$line.table


####################################################################################################################################################
###########################now let's find the best candidates#########################

#snpEff
$java -jar programs/snpEff/snpEff.jar -c programs/snpEff/snpEff.config $snpEffDB -s output/snpEff_summary.html output/$line.hc.vcf > output/$line.se.vcf

###%%%%%%% JEN %%%%%%%%%%
#and finally, get only the SNPs that are ref/ref or ref/alt in the wt bulk and alt/alt in the mut bulk for recessive mutations
#for the case of dominant mutations should be ref/ref in the wt bulk and ref/alt or alt/alt in the mutant bulk
#column 10 is mutant bulk
#column 11 is WT bulk
#for Fusarium the match conditions was changed to scf (instead of [0-9X])

if [ $mutation = "recessive" ]; then
	grep -v '^##' output/$line.se.vcf | awk 'BEGIN{FS=" "; OFS=" "} $1~/#CHROM/ || $10~/^1\/1/ && ($11~/^1\/0/ || $11~/^0\/0/ || $11~/^0\/1/) && ($1~/^[0-9X]*$/ || $1~/scf/) && /splice_acceptor_variant|splice_donor_variant|splice_region_variant|stop_lost|start_lost|stop_gained|missense_variant|coding_sequence_variant|inframe_insertion|disruptive_inframe_insertion|inframe_deletion|disruptive_inframe_deletion|exon_variant|exon_loss_variant|exon_loss_variant|duplication|inversion|frameshift_variant|feature_ablation|duplication|gene_fusion|bidirectional_gene_fusion|rearranged_at_DNA_level|miRNA|initiator_codon_variant|start_retained/ {$3=$7=""; print $0}' | sed 's/  */ /g' | awk '{split($9,a,":"); split(a[2],b,","); if (b[1]>b[2] || $1~/#CHROM/) print $0}' > output/$line.cands2.txt
else
	grep -v '^##' output/$line.se.vcf | awk 'BEGIN{FS=" "; OFS=" "} $1~/#CHROM/ || ($10~/^0\/1/ || $10~/^1\/0/ || $10~/^1\/1/) && $11~/^0\/0/ && $1~/^[0-9X]*$/ && /splice_acceptor_variant|splice_donor_variant|splice_region_variant|stop_lost|start_lost|stop_gained|missense_variant|coding_sequence_variant|inframe_insertion|disruptive_inframe_insertion|inframe_deletion|disruptive_inframe_deletion|exon_variant|exon_loss_variant|exon_loss_variant|duplication|inversion|frameshift_variant|feature_ablation|duplication|gene_fusion|bidirectional_gene_fusion|rearranged_at_DNA_level|miRNA|initiator_codon_variant|start_retained/ {$3=$7=""; print $0}' | sed 's/  */ /g' | awk '{split($9,a,":"); split(a[2],b,","); if (b[1]>b[2] || $1~/#CHROM/) print $0}' > output/$line.cands2.txt
fi


#awk 'FNR==NR{a[$1$2];next};!($1$2 in a) || $1~/#CHROM/' $knownsnps output/$line.cands2.txt > output/$line.cands3.txt


#getting things a bit more organized and only the relevant data from cands3
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "chr" "pos" "ref" "alt" "mutation_effect" "gene" "At_num" "CDS_change" "protein_change" "$mut.ref" "$mut.alt" "$wt.ref" "$wt.alt" > output/$line.cands44.txt
awk 'BEGIN{OFS="\t"} NR>1 {split($6,a,"|");split($8,b,":"); split(b[2],c,","); split($9,d,":"); split(d[2],e,","); gsub("c.", "", a[10]); gsub("p\\.", "", a[11]); print $1, $2, $3, $4, a[2], a[4], a[5], a[10], a[11], c[1], c[2], e[1], e[2]}' output/$line.cands2.txt | awk '$0!~/\./ && (($10+$11)>4) && (($12+$13)>4)' >> output/$line.cands44.txt

# JEN changed file name below

{ head -n 1; sort -t $'\t' -V -k1,1; } < output/$line.cands44.txt > output/$line.candidates.txt


####################################################################################################################################################
####################################################################################################################################################

####################################################################################################################################################
####################################################################################################################################################
#this command will make it ready to run w/ R to produce Manhatten plot
printf "%s\t" "CHR" "POS" "REF" "ALT" "mut_GT" "mut.ref" "mut.alt" "mut.DP" "mut.GQ" "wt.GT" "wt.ref" "wt.alt" "wt.DP" "wt.GQ" > output/$line.plot.txt; printf "\n" >> output/$line.plot.txt
awk '($1~/^[0-9X]*$/ || $1~/scf/) && $5~/^[AGCT]/ && $9~/^[AGCT]/ && $0 !~ /NA/ && $2 !~ /\./ && $3 !~ /\./ {gsub(/\,/, "\t"); print}' output/$line.table | awk '$6+$11>0 && $8>3 && $13>3' >> output/$line.plot.txt

#and finally, just get rid of known snps
awk 'FNR==NR{a[$1$2$4$5];next};!($1$2$3$4 in a)' $knownsnps output/$line.plot.txt > output/$line.plot.no_known_snps.txt

#get the snps in SnpEff format
awk 'FNR==NR{a[$1$2];next};($1$2 in a)' output/$line.plot.no_known_snps.txt output/$line.se.vcf > output/$line.plot2.txt
awk '{$3=$7=""; print $0}' output/$line.plot2.txt | sed 's/  */ /g' > output/$line.plot3.txt
awk '$3!~/\./ && $4!~/\./' output/$line.plot3.txt > output/$line.plot33.txt
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "chr" "pos" "ref" "alt" "mutation_effect" "gene" "At_num" "CDS_change" "protein_change" "mut.ref" "mut.alt" "wt.ref" "wt.alt" > output/$line.plot44.txt
awk 'BEGIN{OFS="\t"} {split($6,a,"|");split($8,b,":"); split(b[2],c,","); split($9,d,":"); split(d[2],e,","); gsub("c.", "", a[10]); gsub("p\\.", "", a[11]); print $1, $2, $3, $4, a[2], a[4], a[5], a[10], a[11], c[1], c[2], e[1], e[2]}' output/$line.plot33.txt >> output/$line.plot44.txt

##JEN changed filename below

{ head -n 1; sort -t $'\t' -V -k1,1; } < output/$line.plot44.txt > output/$line.allSNPs.txt


####################################################################################################################################################
####################################################################################################################################################
#print cands that originate from a non-ref nucleotide
#print cands that originate from a non-ref nucleotide
#grep -v '^##' output/$line.se.vcf | awk 'BEGIN{FS=" "; OFS=" "} $1~/#CHROM/ || ($10~/^2\/2/ && $11!~/^2\/2/) && ($1~/^[0-9X]*$/ || $1~/scf/) && /splice_acceptor_variant|splice_donor_variant|splice_region_variant|stop_lost|start_lost|stop_gained|missense_variant|coding_sequence_variant|inframe_insertion|disruptive_inframe_insertion|inframe_deletion|disruptive_inframe_deletion|exon_variant|exon_loss_variant|exon_loss_variant|duplication|inversion|frameshift_variant|feature_ablation|duplication|gene_fusion|bidirectional_gene_fusion|rearranged_at_DNA_level|miRNA|initiator_codon_variant|start_retained/ {$3=$7=""; print $0}' | sed 's/  */ /g' | awk '{split($9,a,":"); split(a[2],b,","); if (b[1]>b[2] || $1~/#CHROM/) print $0}' > output/$line.cands_alt2.txt
#awk 'FNR==NR{a[$1$2$4$5];next};!($1$2$3$4 in a) || $1~/#CHROM/' $knownsnps output/$line.cands_alt2.txt > output/$line.cands_alt3.txt

#getting things a bit more organized and only the relevant data from cands3
#printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "chr" "pos" "ref" "alt" "mutation_effect" "gene" "At_num" "CDS_change" "protein_change" "$mut.ref" "$mut.alt" "$wt.ref" "$wt.alt" > output/$line.cands_alt4.txt
#awk 'BEGIN{OFS="\t"} NR>1 {split($6,a,"|");split($8,b,":"); split(b[2],c,","); split($9,d,":"); split(d[2],e,","); gsub("c.", "", a[10]); gsub("p\\.", "", a[11]); print $1, $2, $3, $4, a[2], a[4], a[5], a[10], a[11], c[1], c[2], e[1], e[2]}' output/$line.cands_alt3.txt | awk '$0!~/\./ && (($10+$11)>4) && (($12+$13)>4)' >> output/$line.cands_alt4.txt

#removing simlink

####################################################################################################################################################
####################################################################################################################################################

#JEN added the line argument below
Rscript ./scripts/analysis3.R $line

#archiving files
mv ./output/* ./archive/
mv ./archive/$line.*pdf* ./archive/*allSNPs.txt ./archive/$line.candidates.txt ./output/

rm -r /Library/Developer/CommandLineTools/usr/bin/python

echo "$(tput setaf 1)Simple $(tput setaf 3)is $(tput setaf 4)done"

} 2>&1 | tee ./archive/log.txt #with the { at the beginning of the text will redirect all console output to a file and still be visible in the terminal 

#appending the simple.sh and R files to the log file
cat ./scripts/simple.sh >> ./archive/log.txt
cat ./scripts/analysis3.R >> ./archive/log.txt



