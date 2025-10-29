type BindMount = Struct[{
    'src'       => Stdlib::Unixpath,
    'dst'       => Stdlib::Unixpath,
    'mount_dep' => Optional[Stdlib::Unixpath],
    'type'      => Optional[Enum['file', 'directory']],
}]


class archimedes (
  Optional[Array[BindMount]] $bind_mounts,
) {

  ensure_resource('file', '/cvmfs', {ensure => 'directory'})
  file { '/cvmfs/soft.computecanada.ca':
    ensure => 'directory',
    require => File['/cvmfs']
  }
  file { '/cvmfs/soft.computecanada.ca/custom':
    ensure => 'directory',
    require => File['/cvmfs/soft.computecanada.ca']
  }
  $bind_mounts.each |$mount| {
    file { $mount['dst']:
      ensure  => pick($mount['type'], 'directory'),
      require => Exec['cvmfs_config probe']
    }
    mount { $mount['dst']:
      ensure  => 'mounted',
      fstype  => 'none',
      options => 'rw,bind',
      device  => "${mount['src']}",
      require => [
        [File[$mount['dst']], File['/cvmfs_ro'], File['/cvmfs/soft.computecanada.ca/custom']],
      ],
    }
    # ensure that if a mount dependency is specified, if the dependency is remounted, the target will be remounted
    if ($mount['mount_dep']) {
      Mount[$mount['mount_dep']] ~> Mount[$mount['dst']]
      Mount[$mount['mount_dep']] -> File[$mount['dst']]
    }
  }

  Profile::Ceph::Client::Share<| |> -> File<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> Mount<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> User<| tag == 'cvmfs' |>

  exec { 'cvmfs_config probe':
    unless  => 'ls /cvmfs_ro/{soft.computecanada.ca,soft-dev.computecanada.ca,public.data.computecanada.ca,restricted.computecanada.ca}',
    path    => ['/usr/bin'],
    require => [Service['autofs'], Exec['init_default.local']]
  }

  # add automatic mkhomedir
  package { 'oddjob-mkhomedir': }
  ensure_resource('service', 'oddjobd', { 'ensure' => running, 'enable' => true })
  file_line { 'pam_password_auth_oddjob_mkhomedir':
    ensure => present,
    path   => '/etc/pam.d/password-auth',
    line   => 'session     optional      pam_oddjob_mkhomedir.so debug umask=0077',
    notify => Service['oddjobd', 'sssd']
  }
  file_line { 'pam_system_auth_oddjob_mkhomedir':
    ensure => present,
    path   => '/etc/pam.d/system-auth',
    line   => 'session     optional      pam_oddjob_mkhomedir.so debug umask=0077',
    notify => Service['oddjobd', 'sssd']
  }
}
