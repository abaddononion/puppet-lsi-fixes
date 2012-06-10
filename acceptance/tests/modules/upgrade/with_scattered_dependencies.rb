begin test_name "puppet module upgrade (with scattered dependencies)"

step 'Setup'
require 'resolv'; ip = Resolv.getaddress('forge-dev.puppetlabs.lan')
apply_manifest_on master, "host { 'forge.puppetlabs.com': ip => '#{ip}' }"
apply_manifest_on master, <<-'MANIFEST1'
  file { '/usr/share/puppet':
    ensure  => directory,
  }
  file { ['/etc/puppet/modules', '/usr/share/puppet/modules']:
    ensure  => directory,
    recurse => true,
    purge   => true,
    force   => true,
  }
MANIFEST1
on master, puppet("module install pmtacceptance-stdlib --version 0.0.2 --target-dir /usr/share/puppet/modules")
on master, puppet("module install pmtacceptance-java --version 1.6.0 --target-dir /etc/puppet/modules --ignore-dependencies")
on master, puppet("module install pmtacceptance-postgresql --version 0.0.1 --target-dir /etc/puppet/modules --ignore-dependencies")
on master, puppet("module list") do
  assert_output <<-OUTPUT
    /etc/puppet/modules
    ├── pmtacceptance-java (\e[0;36mv1.6.0\e[0m)
    └── pmtacceptance-postgresql (\e[0;36mv0.0.1\e[0m)
    /usr/share/puppet/modules
    └── pmtacceptance-stdlib (\e[0;36mv0.0.2\e[0m)
  OUTPUT
end

step "Upgrade a module that has a more recent version published"
on master, puppet("module upgrade pmtacceptance-postgresql --version 0.0.2") do
  assert_output <<-OUTPUT
    Preparing to upgrade 'pmtacceptance-postgresql' ...
    Found 'pmtacceptance-postgresql' (\e[0;36mv0.0.1\e[0m) in /etc/puppet/modules ...
    Downloading from http://forge.puppetlabs.com ...
    Upgrading -- do not interrupt ...
    /etc/puppet/modules
    └─┬ pmtacceptance-postgresql (\e[0;36mv0.0.1 -> v0.0.2\e[0m)
      ├─┬ pmtacceptance-java (\e[0;36mv1.6.0 -> v1.7.0\e[0m)
      │ └── pmtacceptance-stdlib (\e[0;36mv0.0.2 -> v1.0.0\e[0m) [/usr/share/puppet/modules]
      └── pmtacceptance-stdlib (\e[0;36mv0.0.2 -> v1.0.0\e[0m) [/usr/share/puppet/modules]
  OUTPUT
end

ensure step "Teardown"
apply_manifest_on master, "host { 'forge.puppetlabs.com': ensure => absent }"
apply_manifest_on master, "file { ['/etc/puppet/modules', '/usr/share/puppet/modules']: ensure => directory, recurse => true, purge => true, force => true }"
end
