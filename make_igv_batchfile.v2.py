'''
Usage: 	python make_igv_batchfile.py -s ~{sample_id} -v ~{var_id} -r ~{ref_fasta} -b ~{write_lines(minibam_array)} -o batch.txt
Purpose: write batch.txt file for IGV, given sample id, variant id, reference fasta, and newline-separated file containing minibams
'''

import sys
from optparse import OptionParser

parser = OptionParser()
parser.add_option('-s', '--sid', dest='sample_id', help='sample id')
parser.add_option('-v', '--vid', dest='var_id', help='comma-separated variant ids in chr:pos:ref:alt format')
parser.add_option('-r', '--ref', dest='ref_fasta', help='reference fasta path')
#parser.add_option('-b', '--bam', dest='bamf', help='newline-separated list of mini-bam files')
parser.add_option('-b', '--bams', dest='bams', help='comma-separated string of mini-bam files')
parser.add_option('-o', '--out', dest='outf', help='output filename')

(options, args) = parser.parse_args()

## check that all arguments are present
if None in vars(options).values():
	print('\n'+'## ERROR: missing arguments')
	parser.print_help()
	print('\n')
	sys.exit()

## open output batch file for writing
outfile = open(options.outf, 'w')

## bash header
outfile.write('#!/bin/bash' + '\n')

## set reference genome
outfile.write('genome %s'%(options.ref_fasta) + '\n')

## load each minibam in bam list
'''
with open(options.bamf, 'r') as bamlist:
	for line in bamlist:
		tmp = line.strip()
		outfile.write('load %s'%(tmp) + '\n')
'''
bamlist = options.bams.split(',')
for b in bamlist:
	outfile.write('load %s'%(b) + '\n')


## set output snapshot directory
outfile.write('snapshotDirectory ./' + '\n')

## set navigation to chr:pos-pos
## e.g. 10:126977914:T:G,11:837476:G:C,11:63898232:C:T,12:43384036:G:T,13:45151910:G:T
variant_positions = options.var_id.split(',')
for v in variant_positions:
	chr = "chr"+v.split(':')[0]
	pos = v.split(':')[1]
	ref = v.split(':')[2]
	alt = v.split(':')[3]
	outfile.write('goto %s:%s-%s'%(chr, pos, pos) + '\n')

	## sort base
	outfile.write('sort base' + '\n')

	## set expand 
	outfile.write('expand' + '\n')

	## set max panel height
	outfile.write('maxPanelHeight 500' + '\n')

	## sort base again for good measure
	outfile.write('sort base' + '\n')

	## snapshot command
	## e.g. 13739.p1.chr10_126977914_T_G.png.png
	#outfname = options.sample_id + '.chr' + '_'.join(options.var_id.split(':'))+'.png'
	outfname = options.sample_id + '.' + chr + '_' +  '_'.join([pos, ref, alt]) + '.png'
	#outfname = options.outscreenname
	#outfile.write('snapshot %s.%s.png'%(options.sample_id, options.var_id))
	outfile.write('snapshot %s'%(outfname) + '\n')

	outfile.write('\n')

outfile.write('exit')

outfile.close()
