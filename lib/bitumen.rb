require "rummager"
require "bitumen/version"
require "bitumen/dsl_definition"

if FileTest::exists?(File.join( Rake.application.original_dir, 'local.conf.rb') )
    puts "using local.conf.rb" if Rake.verbose == true
    load File.join( Rake.application.original_dir, 'local.conf.rb')
end

# variables that affect global Docker operations
DOCKER_POSTFIX = "_#{Etc.getlogin}" unless defined? DOCKER_POSTFIX
DOCKER_CNTNR_DEVENV_BASE = 'devenv'
DOCKER_CNTNR_DEVENV = DOCKER_CNTNR_DEVENV_BASE + DOCKER_POSTFIX

if defined? DOCKER_REPO
    Rummager.repo_base = DOCKER_REPO
    else
    Rummager.repo_base = "r#{DOCKER_POSTFIX}"
end

# Host directories to be injected into the running container(s) when started
## We determine this path by looking at the path for the Rake file!
if ! defined? DIR_HOST_SRC
    DIR_HOST_SRC = Rake.application.original_dir
end

if ! defined? DIR_HOST_LARGEFILES
    DIR_HOST_LARGEFILES = File.join( Rake.application.original_dir, "/blobs" )
end

# Container directories used for external mount or volume-bind from other
# containers
#DIR_CNTNR_BUILD="/build"
#DIR_CNTNR_EXTSRC="/extsrc"
#if defined? DIR_HOST_DL
#    DIR_CNTNR_DLCACHE="/downloads"
#end

#GIT_URI_OE="git://git.openembedded.org/meta-openembedded"
#GIT_BRANCH_OE="master"
#DIR_CNTNR_OE="#{DIR_CNTNR_BUILD}/oe"


#DIR_CNTNR_BBCONF="#{DIR_CNTNR_BUILD}/conf"
#FILE_CONF_LOCAL="#{DIR_CNTNR_BBCONF}/local.conf"
#FILE_CONF_BBLAYERS="#{DIR_CNTNR_BBCONF}/bblayers.conf"

# output variables
if ! defined? DOCKER_CNTNR_DEVENV_EXPORT
    DOCKER_CNTNR_DEVENV_EXPORT = DIR_HOST_LARGEFILES + "/" +
    DOCKER_CNTNR_DEVENV_BASE + ".tar.bz2"
end
