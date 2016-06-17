require "rake/clean"
require "rake"

# Create the default task now so that we can enhance it below
Rake::Task.define_task( :'default' )

Rake::Task.define_task( :'docker:containers:start' )
Rake::Task[ :'docker:containers:start' ].add_description("Start docker containers in background")

Rake::Task.define_task( :'docker:containers:stop' )
Rake::Task[ :'docker:containers:stop' ].add_description("Stop docker containers in background")

Rake::Task.define_task( :'docker:containers:clean' )
Rake::Task[ :'docker:containers:clean' ].add_description("Remove docker build product containers")
Rake::Task[ :clean ].enhance( [ :'docker:containers:clean' ] )

Rake::Task.define_task( :'docker:containers:clobber' )
Rake::Task[ :'docker:containers:clobber' ].add_description("Remove all controlled Docker containers including caches")
Rake::Task[ :clobber ].enhance( [ :'docker:containers:clobber' ] )

Rake::Task.define_task( :'docker:images:clean' )
Rake::Task[ :'docker:images:clean' ].add_description("Remove Docker intermediate images")
Rake::Task[ :'docker:images:clean' ].enhance( [ :'docker:containers:clean' ] )
Rake::Task[ :clean ].enhance( [ :'docker:images:clean' ] )

Rake::Task.define_task( :'docker:images:clobber' )
Rake::Task[ :'docker:images:clobber' ].add_description("Remove all controlled Docker temporary images")
Rake::Task[ :'docker:images:clobber' ].enhance( [ :'docker:containers:clobber' ] )
Rake::Task[ :clobber ].enhance( [ :'docker:images:clobber' ] )

Rake::Task.define_task( :'mastics:setup' )
Rake::Task[ :'mastics:setup' ].add_description("Prepare and configure all containers for building")
Rake::Task.define_task( :'mastics:all' )
Rake::Task[ :'mastics:all' ].add_description("Execute all build targets and generate all artifacts")

Rake::Task[ :default ].enhance( [ :'mastics:setup' ] )
