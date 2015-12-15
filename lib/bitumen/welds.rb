require 'rummager'

module Bitumen

    DOCKER_CNTNR_USER = "minion"
    GIT_URI_POKY="git://git.yoctoproject.org/poky.git"
    DEFAULT_BRNCH_POKY="master"
    DIR_CNTNR_BUILD="/build"

    class Weld
        attr_accessor :mastic
        attr_accessor :docker_user
        attr_accessor :needed_test
        attr_accessor :cmd_list
        
        def initialize( new_mastic )
            if ! new_mastic.instance_of?(Bitumen::Mastic)
                raise ArgumentError, "base:#{base.to_string} is not a subclass of Mastic"
            end # if base.instance_of?
            @mastic = new_mastic
            @docker_user = DOCKER_CNTNR_USER
            @needed_test = []
            @exec_list = []
        end # def initialize
        
        def job_name
            "unknown"
        end
                
        def enter_dep_job
            true
        end
        
        ###
        # This is where the real work is done to create the Rummager
        # data structure.
        ###
        def generate_rake
            Rummager::ClickCntnrExec.new self.job_name, {
                :container_name => @mastic.container_name,
                :user => @docker_user,
                :needed_test => @needed_test,
                :exec_list => @exec_list,
            }
        end # generate_rake
        
    end # class Weld
    
    ###
    # This is the generic handler for stuff that needs to be added to a
    # container and for modifications to Yocto configuration files
    ###
    class YoctoLayer < Bitumen::Weld
        attr_accessor :layer_name
        attr_accessor :container_path
        attr_accessor :uri
        attr_accessor :branch

        @@layer_count = 0

        def initialize( new_mastic )
            super( new_mastic )
            @layer_name = "layer_#{@@layer_count +=1}"
            @uri = ""
            @branch = "master"
            @container_path = "/dev/null"
        end # def initialize

        def job_name
            "add_#{@layer_name}"
        end

        def generate_rake
            @exec_list << Rummager::cmd_sudochown(@docker_user,@container_path)
            pokydir = @container_path + "/" + @layer_name
            @exec_list << Rummager::cmd_gitclone(@branch,@uri,pokydir)
            @exec_list << Rummager::cmd_bashexec(
                 "cd #{pokydir} &&"\
                 ". #{pokydir}/oe-init-build-env @container_path"
            )
            @exec_list << {
                :cmd => ["/bin/sh","-c",
                    "echo 'source #{pokydir}/oe-init-build-env #{@container_path}'"\
                    ">> /home/#{@docker_user}/.profile"],
                 :restart_after => true,
            }
            super
        end

    end # class YoctoLayer

    ###
    # This is the essential layer that must be included
    ###
    class YoctoCore < YoctoLayer
        
        def initialize( new_mastic )
            super( new_mastic )
            @layer_name = "poky"
            @uri = Bitumen::GIT_URI_POKY
            @branch = Bitumen::DEFAULT_BRNCH_POKY
            @container_path = "#{Bitumen::DIR_CNTNR_BUILD}"

            @needed_test = ["/bin/sh","-c","! grep -q oe-init-build-env /home/minion/.profile"]
        end # def initialize
        
    end # class YoctoPokyLayer

end # module Bitumen

# Yocto sources ('aka' Poky)
#def Bitumen.weld_git_source(branchname,uri,target)
# {
#:cmd => ["/usr/bin/git","clone","--branch",branchname,uri,target],
#}
#end # def Bitumen.weld_git_source
