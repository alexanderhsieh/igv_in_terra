version 1.0

## Copyright Broad Institute, 2020
##
## This WDL defines the workflow for generating a tarball containing IGV screenshots.
## Each screenshot contains tracks for proband WES, father, mother, and proband WGS.
##
## LICENSING :
## This script is released under the WDL source code license (BSD-3) (see LICENSE in
## https://github.com/broadinstitute/wdl). Note however that the programs it calls may
## be subject to different licenses. Users are responsible for checking that they are
## authorized to run all programs before running this script. Please see the docker
## page at https://hub.docker.com/r/broadinstitute/genomes-in-the-cloud/ for detailed
## licensing information pertaining to the included programs.

###########################################################################
# WORKFLOW DEFINITION
###########################################################################

workflow generate_igv_screenshots {
	input {

		File batch_script # make_igv_batchfile.py

		File input_table

		File ref_fasta
		File ref_fasta_index
		File ref_fasta_dict

		String output_folder_prefix 

	}

	##########################################################################
	## for each variant in input_table, 
	##     1. run GATK PrintReads() to generate mini-crams for pb_WES, fa, mo, pb_WGS
	##     2. run IGV in batch mode to produce single screenshot
	##########################################################################

	## Read in table and coerce as Array[File] corresponding to trios
	## 12-column format
	## 		id, rg_id, var_id, region,
	##      sample WES cram google bucket path, father cram path, mother cram path, sample WGS cram path
	##      sample WES cram index google bucket path, father cram index path, mother cram index path, sample WGS cram index
	call read_table {
		input:
			table = input_table
	}

	## i index (rows) correspond to individual samples
	scatter (i in range(length(read_table.out))) {

		Int n_cols = length(read_table.out[0])

		String sample_id = read_table.out[i][0]
		String rg_id = read_table.out[i][1]
		String var_id = read_table.out[i][2]
		String region = read_table.out[i][3]

		#Array[String] selected_cram_columns = [ read_table.out[i][4], read_table.out[i][5], read_table.out[i][6], read_table.out[i][7] ]
		#Array[String] selected_cram_index_columns = [ read_table.out[i][8], read_table.out[i][9], read_table.out[i][10], read_table.out[i][11] ]

		# note: keep these as strings to avoid localizing large cram files (GATK will stream from bucket)
		String pb_cram = read_table.out[i][4]
		String fa_cram = read_table.out[i][5]
		String mo_cram = read_table.out[i][6]

		call generate_mini_crams {
			input:
				var_id = var_id,
				region = region,
				pb_cram = pb_cram,
				fa_cram = fa_cram,
				mo_cram = mo_cram,
				ref_fasta = ref_fasta,
				ref_fasta_index = ref_fasta_index,
				ref_fasta_dict = ref_fasta_dict
		}

		call run_igv {
			input:
				sample_id = sample_id,
				var_id = var_id,
				ref_fasta = ref_fasta,
				ref_fasta_index = ref_fasta_index,
				script = batch_script,
				pb_bam = generate_mini_crams.mini_pb_bam,
				fa_bam = generate_mini_crams.mini_fa_bam,
				mo_bam = generate_mini_crams.mini_mo_bam,
				pb_bam_index = generate_mini_crams.mini_pb_bam_index,
				fa_bam_index = generate_mini_crams.mini_fa_bam_index,
				mo_bam_index = generate_mini_crams.mini_mo_bam_index		
		}

	}

	call gather_shards {
		input:
			screens = run_igv.screenshot,
			outprefix = output_folder_prefix

	}

	output {
		File screenshots_folder = gather_shards.screenshots_tarball
	}

}


###########################################################################
# TASK DEFINITIONS
###########################################################################

## Reads in <batch>.IGV_input_table.txt to enable coercion from 
## google bucket_path (String) to corresponding gvcf file (File)
## Note: requires specific 12-column format:
## 12-column format
## 		id, rg_id, var_id, region,
##      sample WES cram google bucket path, father cram path, mother cram path, sample WGS cram path
##      sample WES cram index google bucket path, father cram index path, mother cram index path, sample WGS cram index
task read_table {
	input {
		File table
	}

	command { 
		echo "reading table" 
	}

	runtime {
		docker: "ubuntu:latest"
		preemptible: 3
		maxRetries: 3
	}

	output{
		Array[Array[String]] out = read_tsv(table)
	}

}

## Uses GATK PrintReads to generate mini cram files for pb WES, fa, mo, pb WGS
task generate_mini_crams {
	input {

		String var_id

		String region
		
		String pb_cram
		String fa_cram
		String mo_cram
		
		File ref_fasta
		File ref_fasta_index
		File ref_fasta_dict

		Int disk_size = 50

		String project_id = "sfari9100-215419" # test if this google project ID works

	}

	command { 

		## how to set project for --gcs-project-for-requester-pays option??
		gatk PrintReads -I ~{pb_cram} -L ~{region} -O "pb_wes.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
		gatk PrintReads -I ~{fa_cram} -L ~{region} -O "fa.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
		gatk PrintReads -I ~{mo_cram} -L ~{region} -O "mo.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
		#gatk PrintReads -I cram_array[3] -L ~{region} -O "pb_wgs.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
	}

	runtime {
		docker: "broadinstitute/gatk:4.1.8.1"
		memory: "8G"
		disks: "local-disk " + disk_size + " HDD"
		preemptible: 3
		maxRetries: 3
	}

	output {
		File mini_pb_bam = "pb_wes.bam"
		File mini_fa_bam = "fa.bam"
		File mini_mo_bam = "mo.bam"
		File mini_pb_bam_index = "pb_wes.bai"
		File mini_fa_bam_index = "fa.bai"
		File mini_mo_bam_index = "mo.bai"

	}

}

## Run IGV to produce screenshots for 500-bp surrounding each variant
## 4 tracks: sample WES, father, mother, sample WGS
task run_igv {
	input {
		String sample_id
		String var_id
		File ref_fasta
		File ref_fasta_index

		File script

		File pb_bam
		File fa_bam 
		File mo_bam 
		File pb_bam_index 
		File fa_bam_index 
		File mo_bam_index 

		Int disk_size = 100
	}
	String rawprefix = "~{sample_id}.chr~{var_id}"
	String outprefix = sub("~{rawprefix}", ":", "_")
	String outfname = "~{outprefix}.png" # format should be <sample_id>.<chr>*_<pos>_<ref>_<alt>.png

	command { 
		echo ~{outfname}

		## generate IGV batch file + prints out screenshot filename and stores in bash variable $SCREENSHOT
		python ~{script} -s ~{sample_id} -v ~{var_id} -r ~{ref_fasta} -b ~{pb_bam},~{fa_bam},~{mo_bam} -o batch.txt -z ~{outfname}
		

		## RUN IGV IN BATCH MODE
		xvfb-run --server-args="-screen 0, 1920x540x24" bash /IGV_2.4.14/igv.sh -b batch.txt
	}

	runtime {
		docker: "talkowski/igv_gatk:latest"
		memory: "10G"
		disks: "local-disk " + disk_size + " HDD"
		preemptible: 3
		maxRetries: 3
	}

	output {
		File batchfile = "batch.txt"
		File screenshot = "~{outfname}.png"
	}
}

task gather_shards {
	input {
		Array[File] screens
		String outprefix
	}

	command <<<

        echo "creating directory ~{outprefix}/ ..."

        mkdir ~{outprefix}

        echo "copying screenshots into ~{outprefix}/ ..."
        while read file; do
            mv ${file} ~{outprefix}/
        done < ~{write_lines(screens)};

        echo "creating ~{outprefix}.tar.gz ..."
        tar -czf ~{outprefix}.tar.gz ~{outprefix}/

        echo "done!"
    >>>

    runtime {
		docker: "ubuntu:latest"
		preemptible: 3
		maxRetries: 3
	}

    output {
    	File screenshots_tarball = "~{outprefix}.tar.gz"
    }

    

}