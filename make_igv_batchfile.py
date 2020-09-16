'''
Usage: 	python make_igv_batchfile.py -s ~{sample_id} -v ~{var_id} -r ~{ref_fasta} -b ~{write_lines(minibam_array)} -o batch.txt
Purpose: write batch.txt file for IGV, given sample id, variant id, reference fasta, and newline-separated file containing minibams
'''

import sys
from optparse import OptionParser

parser = OptionParser()
parser.add_option('-s', '--sid', dest='sample_id', help='sample id')
parser.add_option('-v', '--vid', dest='var_id', help='variant id in chr:pos:ref:alt format')
parser.add_option('-r', '--ref', dest='ref_fasta', help='reference fasta path')
parser.add_option('-b', '--bam', dest='bamf', help='newline-separated list of mini-bam files')
parser.add_option('-o', '--out', dest='outf', help='output filename')
parser.add_option('-z', '--screen', dest='outscreenname', help='output screenshot filename prefix')

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
with open(options.bamf, 'r') as bamlist:
	for line in bamlist:
		tmp = line.strip()
		outfile.write('load %s'%(tmp) + '\n')

## set output snapshot directory
outfile.write('snapshotDirectory ./' + '\n')

## set navigation to chr:pos-pos
chr = "chr"+options.var_id.split(':')[0]
pos = options.var_id.split(':')[1]
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
#outfname = options.sample_id + '.chr' + '_'.join(options.var_id.split(':'))+'.png'
outfname = options.outscreenname
#outfile.write('snapshot %s.%s.png'%(options.sample_id, options.var_id))
outfile.write('snapshot %s.png'%(outfname) + '\n')

outfile.write('exit')

outfile.close()
