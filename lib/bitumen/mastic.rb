require 'rake'
require 'bitumen/welds'

module Bitumen
    
    DOCKER_REPO_DEFAULT="y3ddet"
    DOCKER_IMAGE_DEFAULT="debian4yocto"
    
    class Mastic
        attr_accessor :add_to_default
        attr_accessor :repo_base
        attr_accessor :image_name
        attr_accessor :binds
        
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
        end # def initialize
        
        def vols_from( new_vols_from )
            @volumes_from.push( new_vols_from )
        end # def add_vols_from

        def weldYoctoLayer(*args)
            new_weld = Bitumen::YoctoLayer.new(self,*args)
            @welds << new_weld
            yield(new_weld) if block_given?
            return new_weld
        end

        def weldYoctoCore
            new_weld = Bitumen::YoctoCore.new(self)
            @welds << new_weld
            yield(new_weld) if block_given?
            return new_weld
        end # def mastic


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
            
            Rummager::ClickContainer.new self.container_name, {
                :repo_base => @repo_base,
                :image_name => @image_name,
                :image_nobuild => true,
                :allow_enter => true,
                :publishall => true,
                :binds => @binds,
                :enter_dep_jobs => enter_dep_jobs,
            }
            #            @volumes_from.each do |vf|
            #            end
            
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