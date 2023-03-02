module Mac::Pkg
  include Beaker::CommandFactory

  def check_for_package(name)
    raise "Package #{name} cannot be queried on #{self}"
  end

  def install_package(name, _cmdline_args = '', _version = nil)
    generic_install_dmg("#{name}.dmg", name, "#{name}.pkg")
  end

  # Install a package from a specified dmg
  #
  # @param [String] dmg_file      The dmg file, including path if not
  #                               relative. Can be a URL.
  # @param [String] pkg_base      The base name of the directory that the dmg
  #                               attaches to under `/Volumes`
  # @param [String] pkg_name      The name of the package file that should be
  #                               used by the installer
  # @example: Install vagrant from URL
  #   mymachost.generic_install_dmg('https://releases.hashicorp.com/vagrant/1.8.4/vagrant_1.8.4.dmg', 'Vagrant', 'Vagrant.pkg')
  def generic_install_dmg(dmg_file, pkg_base, pkg_name)
    execute("test -f #{dmg_file}", :accept_all_exit_codes => true) do |result|
      execute("curl -O #{dmg_file}") unless result.exit_code == 0
    end
    dmg_name = File.basename(dmg_file, '.dmg')
    execute("hdiutil attach #{dmg_name}.dmg")
    execute("installer -pkg /Volumes/#{pkg_base}/#{pkg_name} -target /")
  end

  def uninstall_package(name, _cmdline_args = '')
    raise "Package #{name} cannot be uninstalled on #{self}"
  end

  # Upgrade an installed package to the latest available version
  #
  # @param [String] name          The name of the package to update
  # @param [String] cmdline_args  Additional command line arguments for
  #                               the package manager
  def upgrade_package(name, _cmdline_args = '')
      raise "Package #{name} cannot be upgraded on #{self}"
  end

  #Examine the host system to determine the architecture
  #@return [Boolean] true if x86_64, false otherwise
  def determine_if_x86_64
    result = exec(Beaker::Command.new("uname -a | grep x86_64"), :expect_all_exit_codes => true)
    result.exit_code == 0
  end

  # Gets the path & file name for the puppet agent dev package on OSX
  #
  # @param [String] puppet_collection Name of the puppet collection to use
  # @param [String] puppet_agent_version Version of puppet agent to get
  # @param [Hash{Symbol=>String}] opts Options hash to provide extra values
  #
  # @note OSX does require :download_url to be set on the opts argument
  #   in order to check for builds on the builds server
  #
  # @raise [ArgumentError] If one of the two required parameters (puppet_collection,
  #   puppet_agent_version) is either not passed or set to nil
  #
  # @return [String, String] Path to the directory and filename of the package, respectively
  def puppet_agent_dev_package_info( puppet_collection = nil, puppet_agent_version = nil, opts = {} )
    error_message = "Must provide %s argument to get puppet agent dev package information"
    raise ArgumentError, error_message % "puppet_collection" unless puppet_collection
    raise ArgumentError, error_message % "puppet_agent_version" unless puppet_agent_version
    raise ArgumentError, error_message % "opts[:download_url]" unless opts[:download_url]

    variant, version, arch, codename = self['platform'].to_array

    mac_pkg_name = "puppet-agent-#{puppet_agent_version}"
    version = version[0,2] + '.' + version[2,2] unless version.include?(".")
    # newest hotness
    path_chunk = "apple/#{version}/#{puppet_collection}/#{arch}"
    release_path_end = path_chunk
    # moved to doing this when 'el capitan' came out & the objection was
    # raised that the code name wasn't a fact, & as such can be hard to script
    # example: puppet-agent-0.1.0-1.osx10.9.dmg
    release_file = "#{mac_pkg_name}-1.osx#{version}.dmg"
    if not link_exists?("#{opts[:download_url]}/#{release_path_end}/#{release_file}") # new hotness
      # little older change involved the code name as only difference from above
      # example: puppet-agent-0.1.0-1.mavericks.dmg
      release_file = "#{mac_pkg_name}-1.#{codename}.dmg"
    end
    if not link_exists?("#{opts[:download_url]}/#{release_path_end}/#{release_file}") # oops, try the old stuff
      release_path_end = "apple/#{puppet_collection}"
      # example: puppet-agent-0.1.0-osx-10.9-x86_64.dmg
      release_file = "#{mac_pkg_name}-#{variant}-#{version}-x86_64.dmg"
    end
    return release_path_end, release_file
  end

  # Gets host-specific information for PE promoted puppet-agent packages
  #
  # @param [String] puppet_collection Name of the puppet collection to use
  # @param [Hash{Symbol=>String}] opts Options hash to provide extra values
  #
  # @return [String, String, String] Host-specific information for packages
  #   1. release_path_end Suffix for the release_path. Used on Windows. Check
  #   {Windows::Pkg#pe_puppet_agent_promoted_package_info} to see usage.
  #   2. release_file Path to the file on release build servers
  #   3. download_file Filename for the package itself
  def pe_puppet_agent_promoted_package_info( puppet_collection = nil, opts = {} )
    error_message = "Must provide %s argument to get puppet agent dev package information"
    raise ArgumentError, error_message % "puppet_collection" unless puppet_collection

    variant, version, arch, _codename = self['platform'].to_array
    release_file = "/repos/apple/#{version}/#{puppet_collection}/#{arch}/puppet-agent-*"

    # macOS puppet-agent tarballs haven't always included arch
    agent_version = opts[:puppet_agent_version]
    agent_version_f = agent_version&.to_f

    download_file = if agent_version_f.nil? || (agent_version_f < 6.28 || (agent_version_f >= 7.0 && agent_version_f < 7.18))
                      "puppet-agent-#{variant}-#{version}.tar.gz"
                    else
                      "puppet-agent-#{variant}-#{version}-#{arch}.tar.gz"
                    end

    return '', release_file, download_file
  end

  # Installs a given PE promoted package on a host
  #
  # @param [String] onhost_copy_base Base copy directory on the host
  # @param [String] onhost_copied_download Downloaded file path on the host
  # @param [String] onhost_copied_file Copied file path once un-compressed
  # @param [String] download_file File name of the downloaded file
  # @param [Hash{Symbol=>String}] opts additional options
  #
  # @return nil
  def pe_puppet_agent_promoted_package_install(
    onhost_copy_base, onhost_copied_download, onhost_copied_file, _download_file, _opts
  )
    execute("tar -zxvf #{onhost_copied_download} -C #{onhost_copy_base}")
    # move to better location
    execute("mv #{onhost_copied_file}.dmg .")
    self.install_package("puppet-agent-*")
  end

end
