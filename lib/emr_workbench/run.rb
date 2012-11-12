require 'elasticity'

module EMRWorkbench
  class Run
    def initialize
      emr_manifest = YAML.load_file("manifest.yml")['emr_manifest']
      data_manifest = YAML.load_file("data/data_manifest.yml")['data_manifest']
      scripts_manifest = YAML.load_file("scripts/scripts_manifest.yml")['scripts_manifest']
      
      @input_data = data_manifest['input_files']
      @mapper_script = scripts_manifest['mapper']
      @reducer_script = scripts_manifest['reducer']
      @aws_access_key = emr_manifest['aws_access_key']
      @aws_secret_key = emr_manifest['aws_secret_key']
      @aws_region = emr_manifest['aws_region']
      @output_bucket = emr_manifest['output_bucket']
      
      @emr = Elasticity::EMR.new(@aws_access_key, @aws_secret_key)
    end
    
    def self.start
      run = new
      run.upload
      run.run_job
      run.check_results
      run.download_results
    end

    def upload
      if @input_data[0..1] != 's3'
        puts "Uploading data..."
        s3 = Elasticity::SyncToS3(@input_bucket, @aws_access_key, @aws_secret_key, @aws_region)
        s3.sync(@input_data, "#{@input_data}/data")
      else
        puts "Using data on S3: #{@input_data}"
      end
      
      if @mapper_script[0..1] != 's3'
      
        puts "Uploading map and reduce scripts..."
        s3 = Elasticity::SyncToS3(@scripts_bucket, @aws_access_key, @aws_secret_key, @aws_region)
        s3.sync(@mapper_script, 'remote-dir/this-job')
        s3.sync(@reducer_script, 'remote-dir/this-job')
      else
        puts "Using script on S3: #{@mapper_script}"
      end
    end

    def run_job
      puts "Running job on EMR..."
      jobflow = Elasticity::JobFlow.new(@aws_access_key, @aws_secret_key)

      streaming_step = Elasticity::StreamingStep.new(@input_data, @output_bucket, @mapper_script, @reducer_script)
      jobflow.add_step(streaming_step)
      @jobflow_id = jobflow.run

      puts "Job started: #{@jobflow_id}"
    end

    def check_results
      stop_statuses = ['COMPLETED', 'FAILED', 'TERMINATED']
      state = ''
      state_change = ''
      
      while stop_statuses.include?(state) == false
        last_state_change = state_change
        
        j = @emr.describe_jobflow(@jobflow_id)
        state = j.state
        state_change = j.last_state_change_reason
        print state + ".."
        if state_change != last_state_change
          puts state_change
        end
        sleep 30
      end
      puts "Job completed with status: #{state}"
    end

    def download_results
    end
    
  end

end
