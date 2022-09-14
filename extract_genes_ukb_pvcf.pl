#!/usr/bin/env perl 

use strict;
use JSON;
use File::Spec::Functions;


@ARGV == 5 or die "$0 <pVCF file path> <hg38 gene regions> <pVCF block files> <Targeted gene list> <Output folder> \n";

### The output file in JSON format
### dx run app-swiss-army-knife -f input.json --destination "/ws" -y
# {
#     "cmd": "bcftools view --regions chr14:95086244-95158010 ukb23157_c14_b24_v1.vcf.gz -O z > UKBB_DICER1_500K.vcf.gz", 
#     "in": [
#         {
#             "$dnanexus_link": {
#                 "project": "project-GFk7Z88JbjP3P0Gz6q09vXFX", 
#                 "id": "file-G97bV6jJykJqFjKv34JYVZ9Y"
#             }
#         }, 
#         {
#             "$dnanexus_link": {
#                 "project": "project-GFk7Z88JbjP3P0Gz6q09vXFX", 
#                 "id": "file-G97bj8jJykJbVkp97jxjQ3zJ"
#             }
#         }
#     ]
# }

my $UKB_PVCF_PATH = shift;
my $hg38_reg_fn = shift;
my $block_fn = shift;
my $gene_lst_fn = shift;
my $outdir = shift;


### Parse hg38 genes
open HG38_REG, $hg38_reg_fn or die $!;

# chr     start   end     gene    region
# chr19   58345178        58362751        A1BG    19:58345178-58362751
# chr8    18386311        18401218        NAT2    8:18386311-18401218
# chr20   44619522        44652233        ADA     20:44619522-44652233

<HG38_REG>; 
my %hg38_hash=();

while(<HG38_REG>){
    chomp;
    my @e = split/\t/;
    $hg38_hash{$e[3]} = [@e];    
}
close HG38_REG;

print join("\t", @{$hg38_hash{"A1BG"}})."\n";


###################################################
# Parse block fn
###################################################
# 1       1       0       1       1218130
# 2       1       1       1218131 1426969
# 3       1       2       1426970 1758871

my @blocks = ();

open BLOCKS, $block_fn or die $!;

while(<BLOCKS>){
    chomp;
    my @e = split /\t/;
    push @blocks, [@e]; 
}

close BLOCKS;

###################################################
# get genes
###################################################
open GENES, $gene_lst_fn or die $!;

my @lines = <GENES>;
my @genes = split /[\s,]+/, join("", @lines);

print join(", ", @genes)."\n";

for my $g (@genes){
    # gene, region, [@hits]
    my ($g, $reg, $hits) = find_matches($g, \%hg38_hash, \@blocks);

    if(defined $hits){
        
        my $i=0;
        for my $h (@$hits){
            # 1       1       0       1       1218130
            my $target_fn = sprintf("ukb23157_c%s_b%s_v1.vcf.gz", $h->[1], $h->[2]);
            
            &write2json($g, $reg, $target_fn, $i, $outdir);
            
            
            $i++;
        }
        
        # print "Get: ".join(", ", @objs)."\n\n";


    }
}

my @test2 = find_matches("DUMMY", \%hg38_hash, \@blocks);

#########################################
# Get the dx objex name by the file name
#########################################
sub fn2obj{
    my $fn = shift;
    my $path = shift;

    my $cmd=sprintf("dx find  data --name %s --brief --path '%s' ", $fn, $path);

    my $out=qx{$cmd};

    chomp $out;

    # project-GFk7Z88JbjP3P0Gz6q09vXFX:file-G97bV6jJykJqFjKv34JYVZ9Y
    my @rv = split /:/, $out;
    return @rv;
}

###############################
# Return with array: gene, region, [@hits]
sub find_matches{
    my $gene = shift;
    my $reg_hash = shift;
    my $block_array = shift;

    my $g = $reg_hash->{$gene};
    my @hits = ();

    my @rv = ($gene);


    if(!defined $g){
        warn sprintf("There is no gene %s found! \n", $gene);
        push @rv, undef, undef;
    }else{
        print join("\t", @{$g})."\n";
        # chr19   58345178        58362751        A1BG    19:58345178-58362751
        
        for my $r (@{$block_array}){
            # 1       1       0       1       1218130
            my ($id, $chr, $block, $start, $end) = @{$r};
            if( 'chr'.$chr eq $g->[0] && $start <= $g->[2] && $end >= $g->[1] ){
                push @hits, $r;
            }

        }

        ### process hits
        # The target file name is ukb23157_c14_b24_v1.vcf.gz

        map{ print join("\t", @{$_})."\n"} @hits;

        push @rv, $g->[4], \@hits;
    }

    return @rv; 
} 



############################################
# Output the setting in json format for dx run
############################################
# Now put together the final command and save to josn file
# Every element of in is a hash reference like below:
#         {
#             "$dnanexus_link": {
#                 "project": "project-GFk7Z88JbjP3P0Gz6q09vXFX", 
#                 "id": "file-G97bj8jJykJbVkp97jxjQ3zJ"
#             }
#         }
# bcftools view --regions chr14:95086244-95158010 ukb23157_c14_b24_v1.vcf.gz -O z > UKBB_DICER1_500K.vcf.gz

sub write2json{
    my ($gene, $reg, $target_fn, $i, $outdir) = @_;

    if( ! -d $outdir ){
        mkdir $outdir;    
    }

    my @objs=();

    my ($prj, $obj) = fn2obj($target_fn, $UKB_PVCF_PATH);
    push @objs, [$prj, $obj];

    ($prj, $obj) = fn2obj($target_fn.".tbi", $UKB_PVCF_PATH);
    push @objs, [$prj, $obj];

    my @in=map{
        {
            '$dnanexus_link' => {
                'project' => $_->[0],
                'id' => $_->[1]
            }
        }
    } @objs;

    # need to have chr prefix in the specification of region
    # e.g., --regions chr14:95086244-95158010
    my $json_dat = {
        'cmd' => sprintf("bcftools view --regions chr%s %s -O z > UKBB_500K.%s.%d.vcf.gz", $reg, $target_fn, $gene, $i),
        'in' => \@in
    };

    my $json_fn = catfile($outdir, sprintf("UKBB_500K.%s.%d.json", $gene, $i) );
    open JSON, ">$json_fn" or die $!;

    my $json_str = encode_json $json_dat;
    print JSON $json_str."\n";
    close JSON; 
}