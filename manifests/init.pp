type BindMount = Struct[{
    'src'  => Stdlib::Unixpath,
    'dst'  => Stdlib::Unixpath,
    'type' => Optional[Enum['file', 'directory']],
}]


class archimedes (
  Optional[Array[BindMount]] $bind_mounts,
) {

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
        File[$mount['dst']],
      ],
    }
  }

  Profile::Ceph::Client::Share<| |> -> File<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> Mount<| tag == 'archimedes' |>

  exec { 'cvmfs_config probe':
    unless  => 'ls /cvmfs_ro/soft.computecanada.ca',
    path    => ['/usr/bin'],
    require => [Service['autofs'], Exec['init_default.local']]
  }
}
