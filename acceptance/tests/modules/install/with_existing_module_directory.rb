begin test_name "puppet module install (with existing module directory)"

step 'Setup'
require 'resolv'; ip = Resolv.getaddress('forge-dev.puppetlabs.lan')
apply_manifest_on master, "host { 'forge.puppetlabs.com': ip => '#{ip}' }"
apply_manifest_on master, "file { ['/etc/puppet/modules', '/usr/share/puppet/modules']: ensure => directory, recurse => true, purge => true, force => true }"
apply_manifest_on master, <<-PP
file {
  [
    '/etc/puppet/modules/nginx',
    '/etc/puppet/modules/apache',
  ]: ensure => directory;
  '/etc/puppet/modules/nginx/metadata.json':
    content => '{
      "name": "notpmtacceptance/nginx",
      "version": "0.0.3",
      "source": "",
      "author": "notpmtacceptance",
      "license": "MIT",
      "dependencies": []
    }';
  [
    '/etc/puppet/modules/nginx/extra.json',
    '/etc/puppet/modules/apache/extra.json',
  ]: content => '';
}
PP

step "Try to install an module with a name collision"
on master, puppet("module install pmtacceptance-nginx"), :acceptable_exit_codes => [1] do
  assert_output <<-OUTPUT
    STDOUT> Preparing to install into /etc/puppet/modules ...
    STDOUT> Downloading from http://forge.puppetlabs.com ...
    STDERR> \e[1;31mError: Could not install module 'pmtacceptance-nginx' (latest: v0.0.1)
    STDERR>   Installation would overwrite /etc/puppet/modules/nginx
    STDERR>     Currently, 'notpmtacceptance-nginx' (v0.0.3) is installed to that directory
    STDERR>     Use `puppet module install --dir <DIR>` to install modules elsewhere
    STDERR>     Use `puppet module install --force` to install this module anyway\e[0m
  OUTPUT
end
on master, '[ -f /etc/puppet/modules/nginx/extra.json ]'

step "Try to install an module with a path collision"
on master, puppet("module install pmtacceptance-apache"), :acceptable_exit_codes => [1] do
  assert_output <<-OUTPUT
    STDOUT> Preparing to install into /etc/puppet/modules ...
    STDOUT> Downloading from http://forge.puppetlabs.com ...
    STDERR> \e[1;31mError: Could not install module 'pmtacceptance-apache' (latest: v0.0.1)
    STDERR>   Installation would overwrite /etc/puppet/modules/apache
    STDERR>     Use `puppet module install --dir <DIR>` to install modules elsewhere
    STDERR>     Use `puppet module install --force` to install this module anyway\e[0m
  OUTPUT
end
on master, '[ -f /etc/puppet/modules/apache/extra.json ]'

step "Try to install an module with a dependency that has collides"
on master, puppet("module install pmtacceptance-php --version 0.0.1"), :acceptable_exit_codes => [1] do
  assert_output <<-OUTPUT
    STDOUT> Preparing to install into /etc/puppet/modules ...
    STDOUT> Downloading from http://forge.puppetlabs.com ...
    STDERR> \e[1;31mError: Could not install module 'pmtacceptance-php' (v0.0.1)
    STDERR>   Dependency 'pmtacceptance-apache' (v0.0.1) would overwrite /etc/puppet/modules/apache
    STDERR>     Use `puppet module install --dir <DIR>` to install modules elsewhere
    STDERR>     Use `puppet module install --ignore-dependencies` to install only this module\e[0m
  OUTPUT
end
on master, '[ -f /etc/puppet/modules/apache/extra.json ]'

step "Install an module with a name collision by using --force"
on master, puppet("module install pmtacceptance-nginx --force"), :acceptable_exit_codes => [0] do
  assert_output <<-OUTPUT
    Preparing to install into /etc/puppet/modules ...
    Downloading from http://forge.puppetlabs.com ...
    Installing -- do not interrupt ...
    /etc/puppet/modules
    └── pmtacceptance-nginx (\e[0;36mv0.0.1\e[0m)
  OUTPUT
end
on master, '[ ! -f /etc/puppet/modules/nginx/extra.json ]'

step "Install an module with a name collision by using --force"
on master, puppet("module install pmtacceptance-apache --force"), :acceptable_exit_codes => [0] do
  assert_output <<-OUTPUT
    Preparing to install into /etc/puppet/modules ...
    Downloading from http://forge.puppetlabs.com ...
    Installing -- do not interrupt ...
    /etc/puppet/modules
    └── pmtacceptance-apache (\e[0;36mv0.0.1\e[0m)
  OUTPUT
end
on master, '[ ! -f /etc/puppet/modules/apache/extra.json ]'

ensure step "Teardown"
apply_manifest_on master, "host { 'forge.puppetlabs.com': ensure => absent }"
apply_manifest_on master, "file { '/etc/puppet/modules': recurse => true, purge => true, force => true }"
end
