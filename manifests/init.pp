class archimedes::mgmt {
  file { '/tmp_nfs/logs':
    ensure => 'directory',
    mode   => '1777'
  }
}
class archimedes::publisher {
  file { '/mnt/ephemeral0/var':
    ensure => 'directory',
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }
  file { '/mnt/ephemeral0/var/spool':
    ensure  => 'directory',
    mode    => '0755',
    owner   => 'root',
    group   => 'root',
    require => File['/mnt/ephemeral0/var'],
  }
  file { '/mnt/ephemeral0/var/spool/cvmfs':
    ensure  => 'directory',
    mode    => '0755',
    owner   => 'root',
    group   => 'root',
    require => File['/mnt/ephemeral0/var/spool'],
  }
  file { '/var/spool/cvmfs':
    ensure  => 'directory',
    mode    => '0755',
    owner   => 'root',
    group   => 'root',
  }
  mount { '/var/spool/cvmfs':
    ensure  => 'mounted',
    fstype  => 'none',
    options => 'rw,bind',
    device  => '/mnt/ephemeral0/var/spool/cvmfs',
    require => [File['/mnt/ephemeral0/var/spool/cvmfs'], File['/var/spool/cvmfs']],
  }
  Mount<| tag == 'archimedes' |> -> File<| tag == 'cvmfs_publisher' |>
  file_line { 'challenge_response':
    ensure => absent,
    path   => '/etc/ssh/sshd_config.d/50-redhat.conf',
    line   => 'ChallengeResponseAuthentication no',
    notify => Service['sshd']
  }
  wait_for { 'id libuser':
    exit_code => 0,
    polling_frequency => 10,
    max_retries => 180,
  }
  Profile::Users::Local_user<| |> -> Wait_For['id libuser']
  Wait_For['id libuser'] -> Cvmfs_publisher::Repository<| |>
}
class archimedes::node {
  ensure_resource('file', '/cvmfs', {ensure => 'directory'})
  file { '/mnt/ephemeral0/var':
    ensure => 'directory',
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
  }
  file { '/mnt/ephemeral0/var/lib':
    ensure  => 'directory',
    mode    => '0755',
    owner   => 'root',
    group   => 'root',
    require => File['/mnt/ephemeral0/var'],
  }
  file { '/mnt/ephemeral0/var/lib/cvmfs':
    ensure  => 'directory',
    mode    => '0700',
    owner   => 'cvmfs',
    group   => 'cvmfs',
    require => [File['/mnt/ephemeral0/var/lib'], User['cvmfs']],
  }
  file { '/var/lib/cvmfs':
    ensure  => 'directory',
    mode    => '0700',
    owner   => 'cvmfs',
    group   => 'cvmfs',
    require => User['cvmfs'],
  }
  mount { '/var/lib/cvmfs':
    ensure  => 'mounted',
    fstype  => 'none',
    options => 'rw,bind',
    device  => '/mnt/ephemeral0/var/lib/cvmfs',
    require => [File['/mnt/ephemeral0/var/lib/cvmfs'], File['/var/lib/cvmfs']],
  }

  wait_for { 'cvmfs_mounted':
    query => 'ls /cvmfs_ro/{soft.computecanada.ca,soft-dev.computecanada.ca,public.data.computecanada.ca,restricted.computecanada.ca}',
    exit_code => 0,
    polling_frequency => 10,
    max_retries => 180,
  }
  Wait_For['cvmfs_mounted'] -> Mount<| tag == 'archimedes' |>
  Profile::Users::Local_user<| |> -> Wait_For['cvmfs_mounted']
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

  file_line { 'challenge_response':
    ensure => absent,
    path   => '/etc/ssh/sshd_config.d/50-redhat.conf',
    line   => 'ChallengeResponseAuthentication no',
    notify => Service['sshd']
  }
}

type BindMount = Struct[{
    'src'       => String,
    'dst'       => String,
    'items'     => Array[String],
    'mount_dep' => Optional[String],
    'type'      => Optional[Enum['file', 'directory']],
}]

class archimedes::base {
  $ipa_domain = lookup('profile::freeipa::base::ipa_domain')
  wait_for { 'ipa_https_first':
    query             => "openssl s_client -showcerts -connect ipa:443 </dev/null 2> /dev/null | openssl x509 -noout -text | grep --quiet ipa.${ipa_domain}",
    exit_code         => 0,
    polling_frequency => 5,
    max_retries       => 200,
    refreshonly       => true,
    subscribe         => [
      Package['ipa-client'],
      Exec['ipa-client-uninstall_bad-hostname'],
      Exec['ipa-client-uninstall_bad-server'],
    ],
    before           => Wait_For['ipa_https']
  }
}

class archimedes::binds (
  Optional[Array[BindMount]] $bind_mounts = [],
) {
  Profile::Ceph::Client::Share<| |> -> File<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> Mount<| tag == 'archimedes' |>
  Profile::Ceph::Client::Share<| |> -> User<| tag == 'cvmfs' |>

  Exec<| tag == 'cvmfs' |> -> Mount<| tag == 'archimedes' |>
  file { '/mnt/ephemeral0/tmp':
    ensure => 'directory',
    mode   => '1777',
    owner  => 'root',
    group  => 'root',
  }
  mount { '/tmp':
    ensure => 'mounted',
    fstype => 'none',
    options => 'rw,bind',
    device => '/mnt/ephemeral0/tmp',
    require => File['/mnt/ephemeral0/tmp'],
  }
  file { '/mnt/ephemeral0/bwrap':
    ensure => 'directory',
    mode   => '1777',
    owner  => 'root',
    group  => 'root',
  }
  file { '/bwrap':
    ensure => 'directory',
    mode   => '1777',
    owner  => 'root',
    group  => 'root',
  }
  mount { '/bwrap':
    ensure => 'mounted',
    fstype => 'none',
    options => 'rw,bind',
    device => '/mnt/ephemeral0/bwrap',
    require => [File['/mnt/ephemeral0/tmp'],File['/bwrap']]
  }

  $bind_mounts.each |$mount| {
    $root_dst = $mount['dst']
    $root_src = $mount['src']
    $type     = pick($mount['type'], 'directory')
    $mount['items'].each |Integer $index, String $item| {
      $dst = "$root_dst/$item"
      $src = "$root_src/$item"

      ensure_resource('file', $dst, {ensure => $type})
      mount { $dst:
        ensure  => 'mounted',
        fstype  => 'none',
        options => 'rw,bind',
        device  => "$src",
      }
      # ensure that if a mount dependency is specified, if the dependency is remounted, the target will be remounted
      if ($mount['mount_dep']) {
        Mount[$mount['mount_dep']] ~> Mount[$dst]
        Mount[$mount['mount_dep']] -> File[$dst]
      }
    }
  }
}
