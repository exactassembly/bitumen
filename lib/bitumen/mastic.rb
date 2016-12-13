require 'rake'
require 'bitumen/rake_docker.rb'
require 'bitumen/welds'

module Bitumen
    
    DOCKER_REPO_DEFAULT="y3ddet"
    DOCKER_IMAGE_DEFAULT="debian4yocto"
    DIR_CNTNR_BUILD="/build"
    DOCKER_CNTNR_USER = "minion"
        
    class Mastic
        attr_reader :add_to_default
        attr_accessor :image_repo
        attr_accessor :image_name
        attr_accessor :image_tag
        
        attr_accessor :binds
        
        attr_accessor :cntnr_build_path
        attr_accessor :cntnr_user
        
        def container_name
            @name
        end
        
        def initialize( new_name )
            @name = new_name
            @add_to_default = true
            @image_repo = "unknown"
            @image_name = "unknown"
            @image_tag = "latest"
            @volumes_from = []
            @binds = []
            @welds = []
            @cntnr_build_path = DIR_CNTNR_BUILD
            @cntnr_user = DOCKER_CNTNR_USER
            
        end # def initialize
        
        def DockerImage( image_def )
            @image_name = image_def
            if ( image_def.include?("/"))
                image_parts = image_def.split("/")
                @image_repo = image_parts[0]
                @image_name = image_parts[1]
                if ( @image_name.include?(":"))
                    name_parts = image_name.split(":")
                    @image_name = name_parts[0]
                    @image_tag = name_parts[1]
                end
            end
        end # dockerImage
        
        def VolumesFrom( new_vols_from )
            @volumes_from.push( new_vols_from )
        end # def volumesFrom

        def HostBind( host_path, container_path )
            @binds.push( "#{host_path}:#{container_path}" )
        end # def hostBind

        def DownloadMirror( container_path )
            appendstring = ""
            config_weld = Bitumen::YoctoConfAppendWeld.new(self,appendstring)
            @welds << config_weld
            config_weld.instance_eval(&block) if block_given?
            return config_weld
        end

        def GitClone(new_uri,arghash={},&block)
            new_weld = Bitumen::GitClone.new(self,new_uri,arghash)
            @welds << new_weld
            new_weld.instance_eval(&block) if block_given?
            return new_weld
        end # def gitClone

        def YoctoLayer(new_name,arghash={},&block)
            layer_weld = Bitumen::YoctoLayer.new(self,new_name,arghash)
            @welds << layer_weld
            layer_weld.instance_eval(&block) if block_given?
            return layer_weld
        end # def yoctoLayer

        def YoctoCore(arghash={},&block)
            core_weld = Bitumen::YoctoCore.new(self,arghash)
            @welds << core_weld
            core_weld.instance_eval(&block) if block_given?
            return core_weld
        end # def weldYoctoCore

        def BitbakeTarget(new_target,**arghash,&block)
            target_weld = Bitumen::BitbakeTarget.new(self,new_target,arghash)
            @welds << target_weld
            target_weld.instance_eval(&block) if block_given?
            return target_weld
        end # bitbakeTarget

        ###
        # This is where the real work is done to create the Rummager
        # data structure.
        ###
        def generate_rake
            Rake::Task.define_task( :"mastics:#{@name}:welds:setup" )
            Rake::Task[ :"mastics:setup" ].enhance( [ :"mastics:#{@name}:welds:setup" ] )
            
            Rake::Task.define_task( :"mastics:#{@name}:welds:all" )
            Rake::Task[ :"mastics:all" ].enhance( [ :"mastics:#{@name}:welds:all" ] )
            
            Bitumen::DockerPulledImage.new @image_name, {
                :repo => @image_repo,
                :tag => @image_tag,
            }
            
            Bitumen::DockerContainer.new self.container_name, {
                :image_repo => @image_repo,
                :image_name => @image_name,
                :binds => @binds,
            }

            # this will be the set of jobs we require the container to
            # execute at least once
            jobs = []

            @welds.each do |w|
                w.generate_rake
                if w.rake_target
                    if w.setup_weld?
                        Rake::Task[ :"mastics:#{@name}:welds:setup" ].enhance ( [ :"#{w.rake_target}" ] )
                    else
                        Rake::Task[ :"mastics:#{@name}:welds:all" ].enhance ( [ :"#{w.rake_target}" ] )
                        Rake::Task[ :"#{w.rake_target}" ].enhance ( [ :"mastics:#{@name}:welds:setup" ] )
                    end
                end
            end
            #            @volumes_from.each do |vf|
            #            end
            
            Rake::Task.define_task( :"mastics:#{@name}:shell" )
            Rake::Task[ :"mastics:#{@name}:shell" ].enhance( [ :"docker:containers:#{container_name}:shell" ] )
            #            Rake::Task[ :"docker:containers:#{container_name}:shell" ].enhance( [ :"mastics:#{@name}:welds:all" ] )
        end
        
    end # class Mastic

end # module Bitumen
