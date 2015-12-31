require 'rummager'

module Bitumen

    GIT_URI_POKY="git://git.yoctoproject.org/poky.git"
    DEFAULT_BRNCH_POKY="master"

    class Weld
        attr_reader :mastic
        attr_reader :job_name
        attr_reader :rummager_object
        attr_reader :enter_dep_job

        def initialize( new_mastic )
            if ! new_mastic.instance_of?(Bitumen::Mastic)
                raise ArgumentError, "arg:#{new_mastic.to_string} is not a subclass of Mastic"
            end # if new_mastic.instance_of?
            
            @mastic = new_mastic
            @job_name = "unknown"
            @job_args = {}
            @enter_dep_job = true
            @operations = []
        end # def initialize
        
        # some settings may not be present at real initialization time,
        # so we call this later 'init' function just before we perform the
        # generate_rake steps
        def late_init
            @operations << {
                :type => "chown",
                :user => @mastic.cntnr_user,
                :path => @mastic.cntnr_build_path,
            }
        end
        
        ###
        # This is where the real work is done to create the Rummager
        # data structure.
        ###
        def generate_rake
            self.late_init
            @job_args[:container_name] = @mastic.container_name
            @job_args[:user] = @mastic.cntnr_user
            @job_args[:exec_list] = []
            
            @operations.each do |op|
                op_type = op.delete(:type)
                case op_type
                    when "chown"
                        @job_args[:exec_list] << Rummager::cmd_sudochown(op[:user],
                                                                         op[:path])
                    when "gitclone"
                        @job_args[:exec_list] << Rummager::cmd_gitclone(op[:branch],
                                                                        op[:uri],
                                                                        op[:path])
                    when "sed"
                        @job_args[:exec_list] << {
                            :cmd=> [ "/bin/sed","-e",op[:sedcmd],"-i",op[:filetarget] ]
                        }
                    when "bash"
                        cmdstring = op.delete(:cmd)
                        exec_hash = {
                            :cmd => ["/bin/bash","-c",cmdstring],
                        }
                        exec_hash.merge(op)
                        @job_args[:exec_list] << exec_hash
                    else
                        raise ArgumentError, "Unknown git operation '#{gop[:operation]}'"
                end #case op[:type]
                
            end #@operations.each
            
            @rummager_object = Rummager::ClickCntnrExec.new self.job_name, @job_args
        end # generate_rake
        
    end # class Weld
    
    ###
    # This is the generic handler for stuff that needs to be added to a
    # container and for modifications to Yocto configuration files
    ###
    class YoctoLayerCommon < Bitumen::Weld
        attr_accessor :layer_name
        attr_accessor :uri
        attr_accessor :branch

        @@layer_count = 0

        def initialize( new_mastic, new_layer_name, new_uri )
            super( new_mastic )
            @layer_name = new_layer_name
            @job_name = "add_" + new_layer_name
            @uri = new_uri
            @branch = "master"
        end # def initialize
        
        def target_path
            @mastic.cntnr_build_path + "/" + @layer_name
        end
        
        def late_init
            super
            
            @operations << {
                :type => "gitclone",
                :branch => @branch,
                :uri => @uri,
                :path => target_path,
            }
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
            
            @job_args[:needed_test] = ["/bin/sh","-c","! grep -q #{target_path} #{layersfile}"]
            
            sed_string = "  \\%/build/poky/meta-yocto-bsp% a\\\n"\
            "  #{target_path} \\\\"
            @operations << {
                :type => "sed",
                :filetarget => layersfile,
                :sedcmd => sed_string,
            }
        end
        
    end # class YoctoLayer


    ###
    # This is the essential layer that must be included
    ###
    class YoctoCore < YoctoLayerCommon
        
        def initialize( new_mastic )
            super( new_mastic, "poky", Bitumen::GIT_URI_POKY )
            @branch = Bitumen::DEFAULT_BRNCH_POKY
        end # def initialize

        def late_init
            super
            profile_path = "/home/" + @mastic.cntnr_user + "/.profile"
            
            @job_args[:needed_test] = ["/bin/sh","-c","! grep -q oe-init-build-env #{profile_path}"]

            @operations << {
                :type => "bash",
                :cmd => "cd #{target_path} && "\
                        ". ./oe-init-build-env #{@mastic.cntnr_build_path}/",
            }

            @operations << {
                :type => "bash",
                :cmd => "echo 'source #{target_path}/oe-init-build-env #{@mastic.cntnr_build_path}' "\
                        ">> #{profile_path}",
                :restart_after => true,
            }
        end
        
    end # class YoctoPokyLayer

end # module Bitumen

# Yocto sources ('aka' Poky)
#def Bitumen.weld_git_source(branchname,uri,target)
# {
#:cmd => ["/usr/bin/git","clone","--branch",branchname,uri,target],
#}
#end # def Bitumen.weld_git_source
