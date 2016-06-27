require 'rake'
require 'logger'
require 'rake/tasklib'
require 'docker'
require 'date'
require 'digest'
require 'json'
require 'excon'
require 'time'

# allow long runs through Excon, otherwise commands that
# take a long time will fail due to timeout
Excon.defaults[:write_timeout] = 30000
Excon.defaults[:read_timeout] = 30000

# provide Docker verboseness
if Rake.application.options.trace == true
    Docker.logger = Logger.new(STDOUT)
    Docker.logger.level = Logger::DEBUG
end

module Bitumen


    ###########################################################
    ##
    ## Image Handling Pieces
    ##
    ###########################################################

    ##
    # Abstract base class for Image handling tasks
    #
    class ImageTaskBase < Rake::Task
        attr_accessor :image_name
        attr_accessor :repo
        attr_accessor :tag
        
        def has_repo?
            Docker::Image.all(:all => true).any? { |image| image.info['RepoTags'].any? { |s| s.include?(@repo) } }
        end
        
    end # class ImageTaskBase

    ##
    # Rake task to have the Docker daemon pull an image from dockerhub
    #
    class ImagePullTask < ImageTaskBase
        
        def initialize(task_name,app)
            super(task_name,app)
            @actions << Proc.new {
                puts "Image '#{@repo}:#{@image_name}' begin pull"
                Docker::Image.create('fromImage' => "#{@repo}/#{@image_name}:#{@tag}" )
            }
        end
        
        def needed?
            puts "checking for #{@repo}/#{@image_name}" if Rake.verbose == true
            !Docker::Image.all(:all => true).any? { |image| image.info['RepoTags'].any? { |s| s.include?("#{@repo}/#{@image_name}:#{@tag}") } }
        end
        
    end # class ImagePullTask

    # Image removal tasks
    class ImageRMITask < ImageTaskBase
        
        def needed?
            has_repo?
        end
        
        def initialize(task_name, app)
            super(task_name,app)
            @actions << Proc.new {
                puts "removing image '#{@repo}'" if Rake.verbose == true
                Docker::Image.all(:all => true).each do |img|
                    if img.info['RepoTags'].any? { |s| s.include?(@repo) }
                        begin
                            img.delete(:force => true)
                            rescue Exception => e
                            puts "exception: #{e.message}" if Rake.verbose == true
                        end
                    end
                end #each
            }
        end # initialize
        
    end # class ImageRMITask


    ##
    # TaskLib wrapper to generate tasks for images pulled from DockerHub
    #
    class DockerPulledImage < Rake::TaskLib
        
        attr_accessor :image_name
        attr_accessor :image_repo
        attr_accessor :image_tag
        
        def initialize(image_name,**args)
            @image_name = image_name
            @image_repo = args.delete(:repo)
            @image_tag = args.delete(:tag)
            yield self if block_given?
            define
        end
        
        def define
            puts "prepareing pulled image '#{@image_repo}/#{@image_name}:#{@imagetag}'" if Rake.verbose == true
            
            pulltask = ImagePullTask.define_task :"docker:images:#{@image_name}:pull"
            pulltask.image_name = @image_name
            pulltask.repo = @image_repo
            pulltask.tag = @image_tag
            
            preptask = Rake::Task.define_task :"docker:images:#{@image_name}:prepare"
            preptask.enhance( [ :"docker:images:#{@image_name}:pull" ] )
            
            rmitask = ImageRMITask.define_task :"docker:images:#{@image_name}:rmi"
            rmitask.repo = "#{@repo_base}/#{@image_name}"
            Rake::Task[ :"docker:images:clobber" ].enhance( [ :"docker:images:#{@image_name}:rmi" ] )
        end # define
        
    end # class DockerPulledImage


    CNTNR_ARGS_CREATE = {
        'AttachStdin' => true,
        'AttachStdout' => true,
        'AttachStderr' => true,
        'OpenStdin' => true,
        'Tty' => true,
    }
    
    ###########################################################
    ##
    ## Container Handling Pieces
    ##
    ###########################################################
    
    # Abstract base class for Container tasks
    class ContainerTaskBase < Rake::Task
        attr_accessor :container_name
        
        def docker_obj
            begin
                @container_obj ||= Docker::Container.get(@container_name.to_s)
            rescue
                puts "WARNING: unable to locate docker container '#{@container_name}'"
            end
        end
        
        def has_container?
            ! docker_obj.nil?
        end
        
        def is_running?
            container_obj.json['State']['Running'] == false
        end
        
        def exit_code
            container_obj.json['State']['ExitCode']
        end
        
    end # ContainerTaskBase
    
    class ContainerCreateTask < Bitumen::ContainerTaskBase
        attr_accessor :docker_args
        attr_accessor :image_name
        
        def needed?
            ! has_container?
        end
        
        def initialize(task_name, app)
            super(task_name,app)
            @docker_args = {}
            @actions << Proc.new {
                @docker_args['Image'] = @image_name
                @docker_args['name'] = @container_name
                if ! @docker_args.has_key?('Cmd')
                    @docker_args['Cmd'] = ["-c","touch /tmp/keeprunning;while [[ -e /tmp/keeprunning ]]; do sleep 30; done"]
                end
                newcont = Docker::Container.create( @docker_args )
                puts "created container '#{@container_name}' -> #{newcont.json}" if Rake.verbose == true
            }
        end
        
    end #ContainerCreateTask
    
    class ContainerRMTask < Bitumen::ContainerTaskBase
        
        def needed?
            puts "checking needed? for rm:#{@container_name}" if Rake.verbose == true
            has_container?
        end
        
        def initialize(task_name, app)
            super(task_name,app)
            @actions << Proc.new {
                puts "removing container #{@name}:#{docker_obj.to_s}" if Rake.verbose == true
                docker_obj.delete(:force => true, :v => true)
            }
        end #initialize
        
    end #ContainerRMTask

    class ContainerStartTask < Bitumen::ContainerTaskBase
        attr_accessor :volumes_from
        attr_accessor :args_start
        attr_accessor :binds
        attr_accessor :port_bindings
        attr_accessor :publishall
        attr_accessor :exec_on_start
        attr_accessor :start_once
        
        def needed?
            if has_container?
                puts "checking if #{@container_name} is running" if Rake.verbose == true
                if docker_obj.json['State']['Running'] == false
                    puts "#{@container_name} is NOT running"  if Rake.verbose == true
                    if Time.parse(docker_obj.json['State']['StartedAt']) != Time.parse('0001-01-01T00:00:00Z')
                        puts "#{@container_name} previously ran"  if Rake.verbose == true
                        if @start_once == true
                            puts "#{@container_name} is a start_once container, not needed" if Rake.verbose == true
                            return false
                        end
                    else
                        puts "#{@container_name} has never run" if Rake.verbose == true
                    end
                else
                    puts "#{@container_name} is running" if Rake.verbose == true
                end
            else
                puts "#{@container_name} doesnt exist" if Rake.verbose == true
            end
            true
        end
        
        def initialize(task_name, app)
            super(task_name,app)
            @actions << Proc.new {
                start_args = Hash.new
                puts "args:#{@args_start}"
                if @volumes_from
                    puts "using VF:#{@volumes_from}"  if Rake.verbose == true
                    start_args.merge!( {'VolumesFrom' => @volumes_from} )
                end
                if @binds
                    puts "using BINDS:#{@binds}"  if Rake.verbose == true
                    start_args['Binds'] = @binds
                end
                if @port_bindings
                    puts "using PortBindings:#{@port_bindings}"  if Rake.verbose == true
                    start_args['PortBindings'] = @port_bindings
                end
                if @publishall
                    start_args['PublishAllPorts'] = true
                end
                puts "Starting: #{@container_name}"
                docker_obj.start( start_args )
                if @exec_on_start
                    begin
                        puts "issuing exec calls" if Rake.verbose == true
                        exec_on_start.each do |ae|
                            if ae.delete(:hide_output)
                                docker_obj.exec(ae.delete(:cmd),ae)
                                else
                                docker_obj.exec(ae.delete(:cmd),ae) { |stream,chunk| puts "#{chunk}" }
                            end
                            puts "all exec calls complete" if Rake.verbose == true
                        end
                        rescue => ex
                        raise IOError, "exec failed:#{ex.message}"
                    end
                end # @exec_on_start
            }
        end # initialize
        
    end #ContainerStartTask


    class ContainerStopTask < Bitumen::ContainerTaskBase
        
        def needed?
            if has_container?
                docker_obj.json['State']['Running'] == true
            else
                false
            end
        end
        
        def initialize(task_name, app)
            super(task_name,app)
            @actions << Proc.new {
                puts "Stopping #{@container_name}" if Rake.verbose == true
                docker_obj.stop
            }
        end
        
    end #ContainerStopTask




    ##
    # Wrapper to generate tasks for Container lifecycle
    class DockerContainer < Rake::TaskLib
        attr_accessor :container_name
        attr_accessor :image_repo
        attr_accessor :image_name
        attr_accessor :binds
        
        def image_repo_name
            if defined?(@image_repo)
                return "#{@image_repo}/#{@image_name}"
            end
            @image_name
        end
        
        def initialize(container_name,**args)
            @container_name = container_name
            @image_repo = args.delete(:image_repo)
            @image_name = args.delete(:image_name) || container_name
            @binds = args.delete(:binds)
            if !args.empty?
                raise ArgumentError, "'#{@container_name}' defenition has unused/invalid key-values:#{args}"
            end
            
            # execute any
            yield self if block_given?
            
            createtask = Bitumen::ContainerCreateTask.define_task :"docker:containers:#{@container_name}:create"
            createtask.container_name = @container_name
            createtask.image_name = image_repo_name
            createtask.enhance( [ :"docker:images:#{@image_name}:prepare" ] )
            
            # start task
            starttask = Bitumen::ContainerStartTask.define_task :"docker:containers:#{@container_name}:start"
            starttask.container_name = @container_name
            starttask.args_start = @args_start
            starttask.volumes_from = @volumes_from
            starttask.binds = @binds
            starttask.port_bindings = @port_bindings
            #            starttask.publishall = @publishall
            #            starttask.exec_on_start = @exec_on_start
            Rake::Task[:"docker:containers:start"].enhance( [ :"docker:containers:#{@container_name}:start" ] )
            Rake::Task[:"docker:containers:#{@container_name}:start"].enhance( [ :"docker:containers:#{@container_name}:create"  ] )

            # stop task
            stoptask = Bitumen::ContainerStopTask.define_task :"docker:containers:#{@container_name}:stop"
            stoptask.container_name = @container_name
            Rake::Task[:"docker:containers:stop"].enhance( [ :"docker:containers:#{@container_name}:stop" ] )

            # remove task
            rmtask = Bitumen::ContainerRMTask.define_task :"docker:containers:#{@container_name}:rm"
            rmtask.container_name = @container_name
            Rake::Task[ :"docker:containers:#{@container_name}:rm" ].enhance( [ :"docker:containers:#{@container_name}:stop" ] )
            
            #                    if @noclean == true
            #                        Rake::Task[:"containers:clobber"].enhance( [ :"containers:#{@container_name}:rm" ] )
            #                        else
            #                        Rake::Task[:"containers:clean"].enhance( [ :"containers:#{@container_name}:rm" ] )
            #                    end
            #
            
        end
        
    end # class DockerContainer
    

    class DockerExecTask < Bitumen::ContainerTaskBase
        attr_accessor :exec_list
        attr_accessor :ident_hash
        attr_accessor :needed_test
        attr_accessor :user
        
        def ident_filename
            "/.once-#{@ident_hash}"
        end
        
        def needed?
            if ! @needed_test.nil?
                puts "running needed_test '#{needed_test}' in '#{@container_name}'" if Rake.verbose == true
                begin
                    return_arry = docker_obj.exec(@needed_test)
                    puts "test '#{needed_test}' => '#{return_arry[0]}':#{return_arry[2]}"  if Rake.verbose == true
                    return (0 == return_arry[2])
                    rescue => ex
                    puts "test '#{needed_test}' failed in '#{@container_name}':#{ex.message}"
                    return false
                end
            end
            # no ident hash, or not found
            true
        end
        
        def initialize(task_name, app)
            super(task_name,app)
            @actions << Proc.new {
                
                puts ">>executing task: #{task_name}"
                @exec_list.each do |e|
                    
                    cmd = e.delete(:cmd)
                    opts = { :user => @user }
                    restart_after = e.delete(:restart_after)
                    
#                    if hide_output == true
#                        docker_obj.exec(cmd,opts)
#                    else
                        opts[:tty] = true
                        docker_obj.exec(cmd,opts) { |stream, chunk| puts "#{stream}" }
#                    end

                    if restart_after==true
                        puts "exec item requires container restart" if Rake.verbose == true
                        docker_obj.restart()
                    end
                    
                end # @exec_list.each
                puts "<<completed task: #{task_name}"
                
            }
            
        end # initialize
        
    end # class ContainerExecTask


    class DockerExec < Rake::TaskLib
        attr_accessor :job_name
        attr_accessor :container_name
        attr_accessor :exec_list
        attr_accessor :needed_test
        attr_accessor :ident_hash
        attr_accessor :dep_jobs
        attr_accessor :user
        
        def initialize(job_name,args={})
            @job_name = job_name
            if !args.delete(:run_always)
                @ident_hash = Digest::MD5.hexdigest(args.to_s)
                puts "#{job_name} ident: #{@ident_hash}" if Rake.verbose == true
            end
            
            @container_name = args.delete(:container_name)
            if !defined? @container_name
                raise ArgumentError, "ClickContainer'#{@job_name}' missing comtainer_name:#{args}"
            end
            @exec_list = args.delete(:exec_list)
            @dep_jobs = args.delete(:dep_jobs)
            @needed_test = args.delete(:needed_test)
            @user = args.delete(:user)
            if !args.empty?
                raise ArgumentError, "ClickExec'#{@job_name}' defenition has unused/invalid key-values:#{args}"
            end
            yield self if block_given?
            define
        end  # initialize
        
        
        def define
            
            exectask = DockerExecTask.define_task :"docker:containers:#{@container_name}:jobs:#{job_name}"
            exectask.container_name = @container_name
            exectask.exec_list = @exec_list
            exectask.ident_hash = @ident_hash
            exectask.needed_test = @needed_test
            exectask.user = @user
            Rake::Task[:"docker:containers:#{@container_name}:jobs:#{job_name}"].enhance( [:"docker:containers:#{@container_name}:start"] )
            if @dep_jobs
                @dep_jobs.each do |dj|
                    Rake::Task["docker:containers:#{@container_name}:jobs:#{job_name}"].enhance([ :"docker:containers:#{@container_name}:jobs:#{dj}" ])
                end
            end
            
        end # define
        
    end # class ClickCntnrExec

end   # module Bitumen

__END__
