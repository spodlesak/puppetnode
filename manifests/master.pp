class puppetnode::master(
  $server_jvm_max_heap_size = '4096m',
  $server_jvm_min_heap_size = '2048m',
  $puppet_package_version = undef,
  $server_version = undef,
  $server_puppetserver_version = undef
) {

  case $facts['operatingsystemmajrelease'] {
    '9': {
      $puppet_package_version_to_use      = pick($puppet_package_version, '6.2.0-1stretch')
      $server_version_to_use              = pick($server_version, '6.2.0-1stretch')
      $server_puppetserver_version_to_use = pick($server_puppetserver_version, '6.2.0')
      $puppet_collections                 = 'stretch'
      $release_package                    = 'puppet-release-stretch.deb'
      $ruby_packages                      = ['ruby', 'build-essential']
    }
    '10': {
      $puppet_package_version_to_use      = pick($puppet_package_version, '6.2.0-1buster')
      $server_version_to_use              = pick($server_version, '6.2.0-1buster')
      $server_puppetserver_version_to_use = pick($server_puppetserver_version, '6.2.0')
      $puppet_collections                 = 'buster'
      $release_package                    = 'puppet-release-buster.deb'
      $ruby_packages                      = ['ruby', 'build-essential']
    }
    default: {
      # default - can be anything
      fail("unsupported os release")
    }
  }

  $puppet_repo = "https://apt.puppetlabs.com/"

  #install release package

  exec { 'install-collection':
    command => "wget ${puppet_repo}${release_package};dpkg -i /tmp/${release_package}",
    user    => 'root',
    path    => '/usr/bin:/usr/sbin:/bin:/usr/local/bin:/sbin:/usr/local/sbin',
    creates => '/tmp/${release_package}',
    cwd     => '/tmp/',
    require => Package['wget', 'ca-certificates']
  }

# file { '/var/lib/puppet':
#  ensure => link,
#  target => '/opt/puppetlabs/puppet',
#  before => Class['::puppet']
#}

  file { '/etc/puppetserver':
    ensure => link,
    target => '/etc/puppetlabs/puppetserver',
    before => Class['::puppet']
  }

  file { '/etc/puppetdb':
    ensure => link,
    target => '/etc/puppetlabs/puppetdb',
    before => Class['::puppet']
  }

#file { '/etc/puppet':
#  ensure => link,
#  target => '/etc/puppetlabs/puppet',
#  before => Class['::puppet']
#}

  class { '::puppet':
    server                      => true,
    server_git_repo             => false,
    server_foreman              => false,
    server_external_nodes       => '',
    server_puppetdb_host        => $::fqdn,
    server_reports              => 'puppetdb',
    server_storeconfigs_backend => 'puppetdb',
    version                     => $puppet_package_version_to_use,
    server_version              => $server_version_to_use,
    server_puppetserver_version => $server_puppetserver_version_to_use,
    server_jvm_min_heap_size    => $server_jvm_min_heap_size,
    server_jvm_max_heap_size    => $server_jvm_max_heap_size,
    server_jvm_extra_args       => '-Dfile.encoding=UTF-8',
  }

  file { '/etc/puppetlabs/puppet/fileserver.conf':
    ensure  => 'file',
    content => template("puppetnode/fileserver.conf.erb"),
    require => Class['::puppet']
  }

# class { 'postgresql::globals':
#   version         => '9.6',
#   postgis_version => '2.1',
# }

  class { 'puppetdb':
    database_validate => false,
    require           => Class['::puppet', 'postgresql::globals'],
  }

  file { '/etc/puppet/files':
    ensure  => 'directory',
    owner   => 'puppet',
    group   => 'puppet',
    require => Class['::puppet']
  }

  file { '/etc/puppet/files/production':
    ensure  => link,
    target  => '../environments/production/files',
    require => Class['::puppet']
  }


  package { $ruby_packages:
    ensure => 'latest'
  }

  exec {'install librarian-puppet':
    command => '/usr/bin/gem install librarian-puppet',
    creates => '/usr/local/bin/librarian-puppet',
    require => Package['ruby'],
  }

  cron { 'remove reports older than 14 days':
    command  => '/usr/bin/find /var/lib/puppet/reports -type f -name "*.yaml" -mtime -14 -delete',
    user     => 'root',
    month    => '*',
    monthday => '*',
    hour     => '*/6',
    minute   => '*',
    require  => Class['::puppet']
  }

  class { '::postfix::server':
    extra_main_parameters => {
      'inet_protocols' => 'ipv4'
    }
  }
}
