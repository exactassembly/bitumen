require "rake"
require "bitumen/rake_tasks"
require "bitumen/mastic"

module Bitumen
    
    module DSL
        
        # create a 'class' variable
        class << self
            attr_accessor :mastics
        end
        @mastics = []
    
        # when the Rakefile is interpreted it will see this as a global keyword
        def Mastic(new_name, &block)
            # create a Mastic object with the name
            new_mastic = Bitumen::Mastic.new(new_name)
            # now cause any supplied block ({} or do ... end)
            new_mastic.instance_eval(&block)
            # attach this to the list
            DSL.mastics << new_mastic
            # cause Rake hierarchy to be populated
            new_mastic.generate_rake
            return new_mastic
        end # def mastic
        
    end # module DSL

end # module Bitumen

# Now actually incorporate the DSL into the top level namespace so
# keywords will work in the bare/global namespace
self.extend Bitumen::DSL