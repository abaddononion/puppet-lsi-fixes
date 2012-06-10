test_name "puppet should remove a crontab entry as expected"
confine :except, :platform => 'windows'

tmpuser = "pl#{rand(999999).to_i}"
tmpfile = "/tmp/cron-test-#{Time.new.to_i}"

create_user = "user { '#{tmpuser}': ensure => present, managehome => false }"
delete_user = "user { '#{tmpuser}': ensure => absent,  managehome => false }"

package_cron = "case $operatingsystem { centos, redhat: {$cron = 'cronie'}\n default: {$cron ='cron'} } package {'cron': name=> $cron, ensure=>present, }"

agents.each do |host|
    step "ensure the user exist via puppet"
    apply_manifest_on host, create_user
    apply_manifest_on host, package_cron

    step "create the existing job by hand..."
    run_cron_on(host,:add,tmpuser,"* * * * * /bin/true")

    step "apply the resource on the host using puppet resource"
    on(host, puppet_resource("cron", "crontest", "user=#{tmpuser}",
                  "command=/bin/true", "ensure=absent")) do
      assert_match(/crontest\D+ensure:\s+removed/, stdout, "Didn't remove crobtab entry for #{tmpuser} on #{host}")
    end

    step "verify that crontab -l contains what you expected"
    run_cron_on(host, :list, tmpuser) do
      assert_no_match(/\/bin\/true/, stderr, "Error: Found entry for #{tmpuser} on #{host}")
    end

    step "remove the crontab file for that user"
    run_cron_on(host, :remove, tmpuser)

    step "remove the user from the system"
    apply_manifest_on host, delete_user
end
