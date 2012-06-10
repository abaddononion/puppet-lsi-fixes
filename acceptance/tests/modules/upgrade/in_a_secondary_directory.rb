begin test_name "puppet module upgrade (in a secondary directory)"

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
on master, puppet("module install pmtacceptance-java --version 1.6.0 --target-dir /usr/share/puppet/modules")
on master, puppet("module list") do
  assert_output <<-OUTPUT
    /etc/puppet/modules (no modules installed)
    /usr/share/puppet/modules
    ├── pmtacceptance-java (\e[0;36mv1.6.0\e[0m)
    └── pmtacceptance-stdlib (\e[0;36mv1.0.0\e[0m)
  OUTPUT
end

step "Upgrade a module that has a more recent version published"
on master, puppet("module upgrade pmtacceptance-java") do
  assert_output <<-OUTPUT
    Preparing to upgrade 'pmtacceptance-java' ...
    Found 'pmtacceptance-java' (\e[0;36mv1.6.0\e[0m) in /usr/share/puppet/modules ...
    Downloading from http://forge.puppetlabs.com ...
    Upgrading -- do not interrupt ...
    /usr/share/puppet/modules
    └── pmtacceptance-java (\e[0;36mv1.6.0 -> v1.7.1\e[0m)
  OUTPUT
end

ensure step "Teardown"
apply_manifest_on master, "host { 'forge.puppetlabs.com': ensure => absent }"
apply_manifest_on master, "file { ['/etc/puppet/modules', '/usr/share/puppet/modules']: ensure => directory, recurse => true, purge => true, force => true }"
end
