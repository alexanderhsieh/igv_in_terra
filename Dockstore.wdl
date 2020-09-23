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

		String sample_id

		String pb_cram # String containing google bucket URI to avoid localizing cram files
		String fa_cram
		String mo_cram

		String region # chr*:*-*
		String var_id # chr:pos:ref:alt

		File batch_script # make_igv_batchfile.py

		File ref_fasta
		File ref_fasta_index
		File ref_fasta_dict

	}

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

	output {
		File batchfile = run_igv.batchfile
		File output_screenshots = run_igv.screenshots
	}

}


###########################################################################
# TASK DEFINITIONS
###########################################################################

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

		String project_id  # test if this google project ID works

	}
	#String region_list = `echo ~{region} | tr , \\n`


	command <<< 

		echo ~{region} | tr , \\n > tmp.region.list

		## how to set project for --gcs-project-for-requester-pays option??
		gatk PrintReads -I ~{pb_cram} -L "tmp.region.list" -O "pb_wes.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
		gatk PrintReads -I ~{fa_cram} -L "tmp.region.list" -O "fa.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
		gatk PrintReads -I ~{mo_cram} -L "tmp.region.list" -O "mo.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
		#gatk PrintReads -I cram_array[3] -L ~{region} -O "pb_wgs.bam" -R ~{ref_fasta} --gcs-project-for-requester-pays ~{project_id}
	>>>

	runtime {
		docker: "broadinstitute/gatk:4.1.8.1"
		memory: "8G"
		disks: "local-disk " + disk_size + " HDD"
		preemptible: 3
		maxRetries: 3
	}

	output{
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

	command { 
		
		## generate IGV batch file + prints out screenshot filename and stores in bash variable $SCREENSHOT
		python ~{script} -s ~{sample_id} -v ~{var_id} -r ~{ref_fasta} -b ~{pb_bam},~{fa_bam},~{mo_bam} -o batch.txt
		

		## RUN IGV IN BATCH MODE
		xvfb-run --server-args="-screen 0, 1920x540x24" bash /IGV_2.4.14/igv.sh -b batch.txt

		## create output directory for screenshots
		mkdir screenshots

		## move screens to new folder
		cp *.png screenshots

		## create tarball of screenshots directory
		tar -czf screenshots.tar.gz screenshots
	}

	runtime {
		docker: "talkowski/igv_gatk:latest"
		memory: "10G"
		disks: "local-disk " + disk_size + " HDD"
		preemptible: 3
		maxRetries: 3
	}

	output{
		File batchfile = "batch.txt"
		File screenshots = "screenshots.tar.gz"
	}
}