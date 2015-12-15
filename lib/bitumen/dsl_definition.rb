require 'bitumen/mastic'

module Bitumen
    module DSL
        class << self
            attr_accessor :mastics
        end
        @mastics = []
    
        def Mastic(new_name, &block)
            new_mastic = Bitumen::Mastic.new(new_name)
            new_mastic.instance_eval(&block)
            DSL.mastics << new_mastic
            return new_mastic
        end # def mastic
        
    end # module DSL

    ###
    # This actually causes the generation of the Rummager/Rake data structures
    # which command the Docker engine, it must be called by the
    # rakefile in order for the DSL to be used
    ###
    def self.do_rake

        # Create the default task and attach the usual activities to it
        # so that a bare invocation of Rake will work as expected
        Rake::Task::define_task :default

        # iterate through mastics to cause the complete Rake hierarchy to
        # be populated
        Bitumen::DSL.mastics.each do |m|
            m.generate_rake
        end

    end # self.do_rake

end # module Bitumen

self.extend Bitumen::DSL