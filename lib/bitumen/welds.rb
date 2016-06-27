require 'bitumen/rake_docker'

module Bitumen

    GIT_URI_POKY="git://git.yoctoproject.org/poky.git"
    DEFAULT_BRNCH_POKY="master"

    class Weld
        attr_reader :mastic
        attr_reader :job_name
        attr_reader :rummager_object

        def initialize( new_mastic )
            if ! new_mastic.instance_of?(Bitumen::Mastic)
                raise ArgumentError, "arg:#{new_mastic.to_string} is not a subclass of Mastic"
            end # if new_mastic.instance_of?
            
            @mastic = new_mastic
            @job_name = "unknown"
            @exec_job_args = {}
            @copy_targets = []
            @weld_operations = []
            
        end # def initialize

        def rake_target
            "docker:containers:#{@mastic.container_name}:jobs:#{@job_name}"
        end

        def setup_weld?
            true
        end
        
        # some settings may not be present at real initialization time,
        # so we call this later 'init' function just before we perform the
        # generate_rake steps
        def late_init
            
        end
        
        ###
        # This is where the real work is done to create the Rummager
        # operations that complete the insertion of this Weld to the
        # yocto installation
        ###
        def generate_rake
            self.late_init
            @exec_job_args[:container_name] = @mastic.container_name
            @exec_job_args[:user] = @mastic.cntnr_user
            @exec_job_args[:exec_list] = []
            
            ###
            # Each operation is some kind of activity that must be performed
            # inside the docker container, we convert the array of @weld_operations
            # into Rummager @exec_list entries which will be converted into
            # docker exec operations.
            #
            # The specific activity is based on the operation :type and any
            # operation specific arguments in the hash
            ###
            
            @weld_operations.each do |op|
                op_type = op.delete(:type)
                case op_type
                    when "chown"
                        @exec_job_args[:exec_list] << {
                            :cmd => [ "sudo","chown","-R",op[:user], op[:path] ]
                        }
                    when "gitclone"
                        cmdstring = "/usr/bin/git clone --branch #{op[:branch]}" \
                                    " #{op[:uri]} #{op[:path]}"
                        @exec_job_args[:exec_list] << {
                            :cmd => [ "/bin/bash","-c",cmdstring ]
                        }
                    when "fileappend"
                        @exec_job_args[:exec_list] << {
                            :cmd => [ "/bin/bash","-c","echo \"#{op[:textblob]}\" >> #{op[:filetarget]}" ]
                        }
                    when "sed"
                        @exec_job_args[:exec_list] << {
                            :cmd=> [ "/bin/sed","-e",op[:sedcmd],"-i",op[:filetarget] ]
                        }
                    when "bitbake"
                        @exec_job_args[:exec_list] << {
                            :cmd=> [ "/bin/bash","-l","-c","bitbake #{op[:target]}" ]
                        }
                    when "bash"
                        cmdstring = op.delete(:cmd)
                        exec_hash = {
                            :cmd => ["/bin/bash","-c",cmdstring],
                        }
                        exec_hash.merge(op)
                        @exec_job_args[:exec_list] << exec_hash
                    else
                        raise ArgumentError, "Unknown weld operation '#{gop[:operation]}'"
                end #case op[:type]
                
            end #@weld_operations.each
        
            if ! @exec_job_args.empty?
                @exec_object = Bitumen::DockerExec.new self.job_name, @exec_job_args
            end
            if ! @copy_targets.empty?
                
            end
        end # generate_rake

    end # class Weld
    
    class GitClone < Bitumen::Weld
        
        attr_accessor :uri
        attr_accessor :branch
        attr_accessor :dirname
        attr_accessor :op_args
        
        def initialize( new_mastic, new_uri, arghash={} )
            super ( new_mastic )
            @dirname = arghash.delete(:dirname) || new_uri.split("/")[-1]
            @uri = new_uri
            @branch = arghash.delete(:branch) || "master"
            @job_name = "fetch_" + @dirname
            @op_args = arghash
        end
        
        def target_path
            @mastic.cntnr_build_path + "/" + @dirname
        end
        
        def late_init
            super
            
            @exec_job_args[:needed_test] = ["test","!","-d",target_path ]
            
            ###
            # Merge op_args into a hash defining the operation to perform
            ###
            @weld_operations << {
                :type => "gitclone",
                :branch => @branch,
                :uri => @uri,
                :path => target_path,
            }.merge!(@op_args)
            
        end
        
    end # class YoctoLayer
    
    
    ###
    # This is the generic handler for stuff that needs to be added to a
    # container and for modifications to Yocto configuration files
    ###
    class YoctoLayerCommon < Bitumen::Weld
        attr_accessor :layer_name
        attr_accessor :path

        @@layer_count = 0

        def initialize( new_mastic, new_layer_name, arghash={} )
            super( new_mastic )
            @layer_name = new_layer_name
            @job_name = "configure_" + new_layer_name
            if (! arghash.has_key?(:path) )
                @path = @layer_name + "/"
            else
                @path = arghash[:path]
            end
            
            # Always Chown the subdirectory before adding in layer files
            # otherwise we might run into ACL issues with the underlying
            # container filesystem
            @weld_operations << {
                :type => "chown",
                :user => @mastic.cntnr_user,
                :path => @mastic.cntnr_build_path,
            }
        end # def initialize

        ##
        # Directory within the container that will hold this layer's files
        def target_path
            if ( "/" == @path[0] )
                @path
            else
                @mastic.cntnr_build_path + "/" + @path
            end
        end

        ##
        # The path within the docker container to the bitbake local configuration file
        def local_conf_file
            @mastic.cntnr_build_path + "/conf/local.conf"
        end

    end # class YoctoLayerCommon

    ###
    # This is the specific handler for non-core layers including adding
    # the right glue into the Yocto configuration files that is generataed
    # by the YoctoCore constructor
    ###
    class YoctoLayer < YoctoLayerCommon

        def late_init
            super
            layersfile = @mastic.cntnr_build_path + "/conf/bblayers.conf"
            
            ###
            # This allows Rummager to test the container contents to see if
            # the operation is required - in this case we look at the
            # layers.conf file to see if the layer directory has been added
            ###
            @exec_job_args[:needed_test] = ["/bin/sh","-c","! grep -q #{target_path} #{layersfile}"]
            
            ###
            # This is a SED operation to add the target_path to the layers.conf
            # file after the standard meta-yocto declaration
            ###
            sed_string = "  \\%/build/poky/meta-yocto-bsp% a\\\n"\
                         "  #{target_path} \\\\"
            
            @weld_operations << {
                :type => "sed",
                :filetarget => layersfile,
                :sedcmd => sed_string,
            }
            
        end
        
    end # class YoctoLayer

    ###
    # This is the essential Yocto core components on which everything else is
    # merged
    ###
    class YoctoCore < YoctoLayerCommon
        attr_accessor :machine_type
        attr_accessor :uri
        attr_accessor :branch
        
        def initialize( new_mastic, arghash={} )
            super( new_mastic, "poky" )
            if (! arghash.has_key?(:machine_type) )
                @machine_type = "UNDEFINED"
            else
                @machine_type = arghash.delete(:machine_type)
            end
            @uri = arghash.delete(:uri) || Bitumen::GIT_URI_POKY
            @branch = arghash.delete(:branch) || Bitumen::DEFAULT_BRNCH_POKY
        end # def initialize
        
        def late_init
            super
            profile_path = "/home/" + @mastic.cntnr_user + "/.profile"
            
            @exec_job_args[:needed_test] = ["/bin/sh","-c","! grep -q oe-init-build-env #{profile_path}"]

            puts "Using Yocto branch:#{@branch} from #{@uri}" if Rake.verbose == true
            @weld_operations << {
                :type => "gitclone",
                :uri => @uri,
                :branch => @branch,
                :path => target_path
            }

            @weld_operations << {
                :type => "bash",
                :cmd => "cd #{target_path} && "\
                ". ./oe-init-build-env #{@mastic.cntnr_build_path}/",
            }

            ###
            # This is the operation that causes the conf/local.conf and other
            # configuration files to be generated from the Yocto sources, until
            # this is executed, there are no layer or config files to be modified
            ###
            @weld_operations << {
                :type => "bash",
                :cmd => "cd #{target_path} && "\
                        ". ./oe-init-build-env #{@mastic.cntnr_build_path}/",
            }

            ###
            # This causes the bitbake/Yocto environment to be part of the shell
            # environment inside the container.
            ###
            @weld_operations << {
                :type => "bash",
                :cmd => "echo 'source #{target_path}/oe-init-build-env #{@mastic.cntnr_build_path}' "\
                        ">> #{profile_path}",
                :restart_after => true,
            }

            @weld_operations << {
                :type => "fileappend",
                :filetarget => local_conf_file,
                :textblob => "MACHINE ?= '#{@machine_type}'",
            }

        end

        ##
        # Directory within the container that will hold this layer's files
        def target_path
            @mastic.cntnr_build_path + "/poky"
        end

    end # class YoctoPokyLayer

    class BitbakeTarget < Bitumen::Weld
        attr_accessor :bitbake_target
        
        def initialize( new_mastic, bitbake_target, arghash={} )
            super ( new_mastic )
            @bitbake_target = bitbake_target
            @job_name = "bitbake_#{@bitbake_target}"
        end # initialize
        
        def late_init
            super
            @weld_operations << {
                :type => "bitbake",
                :target => bitbake_target,
            }
        end
        
        def setup_weld?
            false
        end
        
    end # YoctoBuildTarget


end # module Bitumen
