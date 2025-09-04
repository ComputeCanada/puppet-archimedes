type BindMount = Struct[{
    'src'  => Stdlib::Unixpath,
    'dst'  => Stdlib::Unixpath,
    'type' => Optional[Enum['file', 'directory']],
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
  }

  Profile::Ceph::Client::Share<| |> -> File<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> Mount<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> User<| tag == 'cvmfs' |>

  exec { 'cvmfs_config probe':
    unless  => 'ls /cvmfs_ro/{soft.computecanada.ca,soft-dev.computecanada.ca,public.data.computecanada.ca,restricted.computecanada.ca}',
    path    => ['/usr/bin'],
    require => [Service['autofs'], Exec['init_default.local']]
  }
}
