# OOD Initializer for Multitenant Apps
# Author: Sean Anderson (anderss@wfu.edu)
# Affiliation: HPC Team, Information Systems, Wake Forest University

require 'open3'

# This MultiTenant class encapsulates everything needed to receive the message
# from a Multitenant App and generate the necessary objects and files
class MultiTenant
  def self.jobs
    @jobs ||= begin
      # OOD ADMIN: these are some of the variables that you may want to tweak!
      # Always make sure you keep them consistent with the individual
      # multitenant apps; i.e. database, LLM, dashboard, website, etc.
      # IMPORTANT: to change the encryption key and iv, search for:
      # 'mt_key' and 'mt_iv'

      admin_wckey = 'multitenant'
      admin_sacct_bin = '/usr/bin/sacct'
      admin_sacct_args = [
        '--allocations',
        '--noheader',
        '--parsable2',
        '--state=RUNNING',
        '--format=jobidraw,user,cluster',
        '-a',
        "--wckeys=#{admin_wckey}"
      ]
      admin_squeue_bin = '/usr/bin/squeue'
      admin_squeue_args = [
        '--noheader',
        '--format=%i|%1024j',
        '-j'
      ]
      admin_cipher = 'aes-256-cbc'

      # Some info about the pun and current user
      dataroot = Configuration.dataroot
      current_uid = CurrentUser.uid
      current_user = CurrentUser.name
      current_groups = CurrentUser.group_names

      # Initialize the mt_main hash
      @mt_main = {}

      # RUN sacct command
      # This is the first of the two Slurm commands to retrieve the multitenant jobs.
      # Since it is filters only the wckey and running jobs, it should have a low
      # impact on your Slurm server.
      o_sacct, = Open3.capture3(admin_sacct_bin, *admin_sacct_args)

      # START over-arching IF statement: if no MT jobs are found, do nothing
      unless o_sacct.empty? # if true then NOT empty and MT jobs were found

        ##########################################################################
        # At this point we have confirmed that there are MT jobs in the queue. Now
        # we will loop over the 'sacct' output and parse out the initial details
        # of those jobs. We will start populating the 'mt_main' hash at the same
        # time with the parsed details.
        ##########################################################################

        o_sacct.each_line do |a| # loop over each line of sacct output
          parse_sacct = a.split('|')
          jobid = parse_sacct[0].to_s.strip     # jobid
          submitter = parse_sacct[1].to_s.strip # username of submitter
          cluster = parse_sacct[2].to_s.strip # cluster name
          # start populating the mt_main hash
          @mt_main[jobid] = {
            'info' => {
              'user' => submitter,
              'cluster' => cluster,
              'mt_key' => "#{jobid}#{submitter}",
              'mt_iv' => "#{jobid}#{jobid}"
            }
          }
          # END loop over each line of sacct output
        end

        ##########################################################################
        # The mt_main hash will be in its initial state, with the MT job Slurm Job
        # IDs and some other basic information. We now need to retrieve the "message"
        # payload from the Slurm job name, which we will do in this section.
        ##########################################################################

        # Define the encryption cipher now that we are ready to use it
        cipher = OpenSSL::Cipher.new(admin_cipher)  # define the cipher, but
        cipher.decrypt                              # only if MT jobs were found

        # RUN squeue command
        # This is the second of the two Slurm commands to retrieve the multitenant
        # jobs. The last argument is a list with the keys from mt_main hash, which
        # are the Slurm Job IDs obtained from the first Slurm command. It should
        # also have a very low impact on your Slurm server since it will only
        # query on those specific Slurm Job IDs.
        o_squeue, = Open3.capture3(admin_squeue_bin, *admin_squeue_args, @mt_main.keys.join(','))

        # Looping over each line of the squeue output, we now parse out the elements
        # in the job name
        o_squeue.each_line do |a|
          parse_squeue = a.split('|')
          jobid = parse_squeue[0].to_s.strip      # jobid
          name_old = parse_squeue[1].to_s.strip   # the old job name, not really used for anything
          name_group = parse_squeue[2].to_s.strip # the name of the permitted POSIX group
          name_b64 = parse_squeue[3].to_s.strip   # the base64 encoded message string

          if current_groups.include? name_group # if user is in MT group, do the rest of the stuff
            mt_key_hex = @mt_main[jobid]['info']['mt_key'].unpack1('H*').ljust(64, '0')
            mt_iv_hex = @mt_main[jobid]['info']['mt_iv'].unpack1('H*').ljust(32, '0')

            cipher.key = [mt_key_hex].pack('H*')
            cipher.iv = [mt_iv_hex].pack('H*')

            encrypted_data = Base64.decode64(name_b64)
            unencrypted_data = cipher.update(encrypted_data) + cipher.final

            # now uncompress the decrypted data
            message = ActiveSupport::Gzip.decompress(unencrypted_data).strip.to_s.split('|')

            # now we have the two json "messages" that needs to be converted to hashes.
            # if any mistake was made and the json is not perfect, JSON.parse will produce
            # an error that will not allow the main dashboard to launch. the next section has
            # some simple error handling that will take care of any parsererrors and proceed
            # even if things didn't go smoothly.
            begin
              @mt_main[jobid]['accounting'] = JSON.parse(message[0].strip.gsub("'", '"'))
              @mt_main[jobid]['connection'] = JSON.parse(message[1].strip.gsub("'", '"'))
            rescue JSON::ParserError => e
              puts "MULTITENANT: There was an error parsing the JSON content: #{e}"
              @mt_main.delete(jobid)
            else
              @mt_main[jobid]['info']['db'] =
                "#{dataroot}/batch_connect/db/#{@mt_main[jobid]['accounting']['mti']}"
              @mt_main[jobid]['info']['output'] =
                "#{dataroot}/batch_connect/" \
                "#{@mt_main[jobid]['accounting']['mtd']}/" \
                "output/#{@mt_main[jobid]['accounting']['mti']}"
              @mt_main[jobid]['info']['message'] = "#{name_old}|#{name_group}|#{name_b64}"
              @mt_main[jobid]['info']['message_size'] = "#{name_old}|#{name_group}|#{name_b64}".length
              @mt_main[jobid]['connection']['jobid'] = jobid
              @mt_main[jobid]['connection']['mt_appname'] = @mt_main[jobid]['accounting']['mta']

              # delete "sensitive" values from hash
              @mt_main[jobid]['info'].delete('mt_key')
              @mt_main[jobid]['info'].delete('mt_iv')
            end

          else # ELSE if the user is not in the selected MT group
            @mt_main.delete(jobid) # delete hash entries if user is not in MT group
            # END if user does belong to selected MT group
          end
          # END loop over each line of squeue output
        end

        ##########################################################################
        # This section will write the db and connection.yml files to the appropriate
        # locations. It will only take effect if there are GOOD MT jobs for the
        # current user. There are at least 4 checks that have to be passed before
        # it will ever consider writing the two files.
        ##########################################################################

        # mt_main is fully populated at this point for every mt job
        unless @mt_main.empty? # if mt_main is empty, then there are no GOOD jobs
          @mt_main.each do |jobid, payload| # loop over each pair in mt_main hash
            mt_users = payload['accounting']['mtu'].to_s.strip.split(',')
            # check to see if we are allowed to have a card AND
            # user in user list AND
            # current user is NOT submitting user
            if payload['accounting']['mtm'] == 'card' &&
               mt_users.include?(current_uid.to_s) &&
               !current_user.eql?(payload['user'])
              unless File.exist?(payload['info']['db'].to_s) # check to see if db file does not exist

                mt_db = <<~TEXT
                  {
                  "id":"#{payload['accounting']['mti']}",
                  "cluster_id":"#{payload['info']['cluster']}",
                  "job_id":"#{jobid}",
                  "created_at":#{Time.now.to_i},
                  "token":"#{payload['accounting']['mtd']}",
                  "title":"#{payload['accounting']['mta']} from #{payload['info']['user']} ",
                  "script_type":"basic",
                  "cache_completed":null,
                  "completed_at":null
                  }
                TEXT
                FileUtils.mkdir_p File.dirname(payload['info']['db'])
                File.write(payload['info']['db'].to_s, mt_db.strip.gsub("\n", ''))
                # END if db file exists
              end
              unless File.directory?(payload['info']['output'].to_s) # checks existence of output directory

                mt_connection = payload['connection'].map { |key, value| "#{key}: #{value}" }.join("\n")
                FileUtils.mkdir_p payload['info']['output']
                File.write("#{payload['info']['output']}/connection.yml", "#{mt_connection}\n")
                # END if output directory exists
              end
              # END if allowed to have a card AND user NOT in list AND current user NOT submitter
            end
            # END loop over each pair in mt_main hash
            # @mt_main.delete(jobid) if payload['accounting']['mta'].downcase.include?('debug')
          end
          # END if mt_main is NOT empty
        end

        # END if sacct output empty
      end

      # END begin jobs
    end
    # END self.jobs
  end

  def self.specs
    @mt_main
  end
  # END MultiTenant class
end

# You must set MULTITENANT_ENABLE to true in your environment! The usual file
# for environment variables is here: /etc/ood/config/apps/dashboard/env
MultiTenant.jobs if ENV['MULTITENANT_ENABLE'] == 'true'
