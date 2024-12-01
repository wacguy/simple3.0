#!/bin/bash
#pipeline for mapping EMS mutants
#variables file

#define the path to Java java-1.8.0 version
java='/usr/bin/java'

#gatk Haplotypecaller requires the SPECIFIC command line tools python
export PATH=$PATH:/Library/Developer/CommandLineTools/usr/bin/

#To make sure Haplotypecaller is calling the correct python; this simlink will be removed at the end of simple.sh
sudo ln -s /Library/Developer/CommandLineTools/usr/bin/python3 /Library/Developer/CommandLineTools/usr/bin/python

#input files
mut_files=fastq/*mut*
wt_files=fastq/*wt*

#output names
mutation=recessive #change to dominant if the mutation is dominant
line=fussarium  ##if you prefer, change EMS to the name of your line.  Letters and underscores only.
mut=TR4_mut 
wt=race1_wt 


my_species=Fusarium_oxysporum_f_sp_cubense #paste your species name here to replace Arabidopsis_thaliana
fa=./refs/$my_species.chrs.fa
snpEff_link=`awk -v var="$my_species" 'match($1, var) {print $4}' ./scripts/data_base.txt`
#reference input files that are necessary to run the prograns
knownsnps=./refs/$my_species.vcf
#ftp://ftp.ensemblgenomes.org/pub/plants/release-31/vcf/arabidopsis_thaliana/arabidopsis_thaliana.vcf.gz
snpEffDB=$snpEff_link #paste the snpEff annotated genome name
knownsnps_link=`awk -v var="$my_species" 'match($1, var) {print $3}' ./scripts/data_base.txt`
fasta_link=`awk -v var="$my_species" 'match($1, var) {print $2}' ./scripts/data_base.txt`


#define docker path

#~/Guy-work/EMS-screens/EMS1/pipeline/SIMPLE/simple2.0_arm64_test_docker