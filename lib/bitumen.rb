require "bitumen/version"
require 'rummager'
require 'bitumen/util'

begin
    local_conf_filename = File.join( Rake.application.original_dir, 'local.conf.rb')
    if FileTest::exists?( local_conf_filename )
        require local_conf_filename
    end
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
if !defined? DIR_HOST_DL
    raise ArgumentError, "Your local.conf.rb file does not define DIR_HOST_DL!"
end

## NOTE!!!
## We determine this path by looking at the path for the Rake file!
if ! defined? DIR_HOST_SRC
    DIR_HOST_SRC = Rake.application.original_dir
end

if ! defined? DIR_HOST_LARGEFILES
    DIR_HOST_LARGEFILES = File.join( Rake.application.original_dir, "/blobs" )
end

# variables that affect Container structure (directories)
DIR_BUILD="/build"
DIR_EXTSRC="/extsrc"
DIR_DLCACHE="/downloads"

GIT_URI_OE="git://git.openembedded.org/meta-openembedded"
GIT_BRANCH_OE="master"
DIR_OE="#{DIR_BUILD}/oe"

GIT_URI_POKY="git://git.yoctoproject.org/poky.git"
GIT_BRNCH_POKY="master"
DIR_POKY="#{DIR_BUILD}/poky"

DIR_BBCONF="#{DIR_BUILD}/conf"
FILE_CONF_LOCAL="#{DIR_BBCONF}/local.conf"
FILE_CONF_BBLAYERS="#{DIR_BBCONF}/bblayers.conf"

# output variables
if ! defined? DOCKER_CNTNR_DEVENV_EXPORT
    DOCKER_CNTNR_DEVENV_EXPORT = DIR_HOST_LARGEFILES + "/" +
    DOCKER_CNTNR_DEVENV_BASE + ".tar.bz2"
end
