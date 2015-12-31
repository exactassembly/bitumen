require 'rake'
require 'bitumen/welds'

module Bitumen
    
    DOCKER_REPO_DEFAULT="y3ddet"
    DOCKER_IMAGE_DEFAULT="debian4yocto"
    DIR_CNTNR_BUILD="/build"
    DOCKER_CNTNR_USER = "minion"
    
    class Mastic
        attr_reader :add_to_default
        attr_accessor :repo_base
        attr_accessor :image_name
        attr_accessor :binds
        
        attr_accessor :cntnr_build_path
        attr_accessor :cntnr_user
        
        def container_name
            "#{@name}_devenv"
        end
        
        def initialize( new_name )
            @name = new_name
            @add_to_default = true
            @repo_base = DOCKER_REPO_DEFAULT
            @image_name = DOCKER_IMAGE_DEFAULT
            @volumes_from = []
            @welds = []
            @cntnr_build_path = DIR_CNTNR_BUILD
            @cntnr_user = DOCKER_CNTNR_USER
            
        end # def initialize
        
        def vols_from( new_vols_from )
            @volumes_from.push( new_vols_from )
        end # def vols_from

        def weldYoctoLayer(new_name,new_uri,&block)
            new_weld = Bitumen::YoctoLayer.new(self,new_name,new_uri)
            @welds << new_weld
            new_weld.instance_eval(&block) if block_given?
            return new_weld
        end # def weldYoctoLayer

        def weldYoctoCore(&block)
            new_weld = Bitumen::YoctoCore.new(self)
            @welds << new_weld
            new_weld.instance_eval(&block) if block_given?
            return new_weld
        end # def weldYoctoCore


        ###
        # This is where the real work is done to create the Rummager
        # data structure.
        ###
        def generate_rake
            # this will be the set of jobs we require the container to
            # execute at least once
            enter_dep_jobs = []
            
            @welds.each do |w|
                w.generate_rake
                if w.enter_dep_job
                    enter_dep_jobs << w.job_name
                end
            end
            #            @volumes_from.each do |vf|
            #            end
            
            Rummager::ClickContainer.new self.container_name, {
                :repo_base => @repo_base,
                :image_name => @image_name,
                :image_nobuild => true,
                :allow_enter => true,
                :publishall => true,
                :binds => @binds,
                :enter_dep_jobs => enter_dep_jobs,
            }
            
            if @add_to_default
                Rake::Task[:default].enhance ( [ :"containers:#{container_name}:enter" ] )
            end
        end
        
        #        def gen_rake_code
        #            Rummager::ClickContainer.new CNTNR_DEVENV, {
        #                :image_name => 'debian4yocto',
        #                :image_nobuild => true,
        #                :repo_base => 'y3ddet',
        #                :binds => [
        #                    "#{HOST_EXTSRC_PATH}:#{DIR_EXTSRC}",
        #                    "#{HOST_DLCACHE_PATH}:#{DIR_DLCACHE}",
        #                ],
        #                :publishall => true,
        #                :allow_enter => true,
        #                :enter_dep_jobs => [
        #                    :"add_yocto",
        #                ]
        #            }
        #        end
    end # class Mastic

end # module Bitumen