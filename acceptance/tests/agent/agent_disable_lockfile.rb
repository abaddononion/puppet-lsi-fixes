test_name "the agent --disable/--enable functionality should manage the agent lockfile properly"

#
# This test is intended to ensure that puppet agent --enable/--disable
#  work properly, both in terms of complying with our public "API" around
#  lockfile semantics ( http://links.puppetlabs.com/agent_lockfiles ), and
#  in terms of actually restricting or allowing new agent runs to begin.
#

###############################################################################
# BEGIN UTILITY METHODS - ideally this stuff would live somewhere besides in
#  the actual test.
###############################################################################

# Create a file on the host.
# Parameters:
# [host] the host to create the file on
# [file_path] the path to the file to be created
# [file_content] a string containing the contents to be written to the file
# [options] a hash containing additional behavior options.  Currently supported:
# * :mkdirs (default false) if true, attempt to create the parent directories on the remote host before writing
#       the file
# * :owner (default 'root') the username of the user that the file should be owned by
# * :group (default 'puppet') the name of the group that the file should be owned by
# * :mode (default '644') the mode (file permissions) that the file should be created with
def create_test_file(host, file_rel_path, file_content, options)

  # set default options
  options[:mkdirs] ||= false
  options[:owner] ||= "root"
  options[:group] ||= "puppet"
  options[:mode] ||= "755"

  file_path = get_test_file_path(host, file_rel_path)

  mkdirs(host, File.dirname(file_path)) if (options[:mkdirs] == true)
  create_remote_file(host, file_path, file_content)

#
# NOTE: we need these chown/chmod calls because the acceptance framework connects to the nodes as "root", but
#  puppet 'master' runs as user 'puppet'.  Therefore, in order for puppet master to be able to read any files
#  that we've created, we have to carefully set their permissions
#

  chown(host, options[:owner], options[:group], file_path)
  chmod(host, options[:mode], file_path)

end


# Given a relative path, returns an absolute path for a test file.  Basically, this just prepends the
# a unique temp dir path (specific to the current test execution) to your relative path.
def get_test_file_path(host, file_rel_path)
  File.join(@host_test_tmp_dirs[host.name], file_rel_path)
end


# Check for the existence of a temp file for the current test; basically, this just calls file_exists?(),
# but prepends the path to the current test's temp dir onto the file_rel_path parameter.  This allows
# tests to be written using only a relative path to specify file locations, while still taking advantage
# of automatic temp file cleanup at test completion.
def test_file_exists?(host, file_rel_path)
  file_exists?(host, get_test_file_path(host, file_rel_path))
end

def file_exists?(host, file_path)
  host.execute("test -f \"#{file_path}\"",
               :acceptable_exit_codes => [0, 1])  do |result|
    return result.exit_code == 0
  end
end

def file_contents(host, file_path)
  host.execute("cat \"#{file_path}\"") do |result|
    return result.stdout
  end
end

def tmpdir(host, basename)
  host_tmpdir = host.tmpdir(basename)
  # we need to make sure that the puppet user can traverse this directory...
  chmod(host, "755", host_tmpdir)
  host_tmpdir
end

def mkdirs(host, dir_path)
  on(host, "mkdir -p #{dir_path}")
end

def chown(host, owner, group, path)
  on(host, "chown #{owner}:#{group} #{path}")
end

def chmod(host, mode, path)
  on(host, "chmod #{mode} #{path}")
end




# pluck this out of the test case environment; not sure if there is a better way
cur_test_file = @path
cur_test_file_shortname = File.basename(cur_test_file, File.extname(cur_test_file))

# we need one list of all of the hosts, to assist in managing temp dirs.  It's possible
# that the master is also an agent, so this will consolidate them into a unique set
all_hosts = Set[master, *agents]

# now we can create a hash of temp dirs--one per host, and unique to this test--without worrying about
# doing it twice on any individual host
@host_test_tmp_dirs = Hash[all_hosts.map do |host| [host.name, tmpdir(host, cur_test_file_shortname)] end ]

# a silly variable for keeping track of whether or not all of the tests passed...
all_tests_passed = false

###############################################################################
# END UTILITY METHODS
###############################################################################



###############################################################################
# BEGIN TEST LOGIC
###############################################################################


# this begin block is here for handling temp file cleanup via an "ensure" block at the very end of the
# test.
begin

  tuples = [
      ["reason not specified", false],
      ["I'm busy; go away.'", true]
  ]

  step "start the master" do
    with_master_running_on(master, "--autosign true") do

      tuples.each do |expected_message, explicitly_specify_message|

        step "disable the agent; specify message? '#{explicitly_specify_message}', message: '#{expected_message}'" do
          agents.each do |agent|
            if (explicitly_specify_message)
              run_agent_on(agent, "--disable \"#{expected_message}\"")
            else
              run_agent_on(agent, "--disable")
            end

            agent_disabled_lockfile = "#{agent['puppetvardir']}/state/agent_disabled.lock"
            unless file_exists?(agent, agent_disabled_lockfile) then
              fail_test("Failed to create disabled lock file '#{agent_disabled_lockfile}' on agent '#{agent}'")
            end
            lock_file_content = file_contents(agent, agent_disabled_lockfile)
            # This is a hack; we should parse the JSON into a hash, but I don't think I have a library available
            #  from the acceptance test framework that I can use to do that.  So I'm falling back to <gasp> regex.
            lock_file_content_regex = /"disabled_message"\s*:\s*"#{expected_message}"/
            unless lock_file_content =~ lock_file_content_regex
              fail_test("Disabled lock file contents invalid; expected to match '#{lock_file_content_regex}', got '#{lock_file_content}' on agent '#{agent}'")
            end
          end
        end

        step "attempt to run the agent (message: '#{expected_message}')" do
          agents.each do |agent|
            run_agent_on(agent, "--no-daemonize --verbose --onetime --test --server #{master}",
                         :acceptable_exit_codes => [1]) do
              disabled_regex = /administratively disabled.*'#{expected_message}'/
              unless result.stdout =~ disabled_regex
                fail_test("Unexpected output from attempt to run agent disabled; expecting to match '#{disabled_regex}', got '#{result.stdout}' on agent '#{agent}'")
              end
            end
          end
        end

        step "enable the agent (message: '#{expected_message}')" do
          agents.each do |agent|

            agent_disabled_lockfile = "#{agent['puppetvardir']}/state/agent_disabled.lock"
            run_agent_on(agent, "--enable")
            if file_exists?(agent, agent_disabled_lockfile) then
              fail_test("Failed to remove disabled lock file '#{agent_disabled_lockfile}' on agent '#{agent}'")
            end
          end

        step "verify that we can run the agent (message: '#{expected_message}')" do
          agents.each do |agent|
            run_agent_on(agent)
            end
          end
        end

      end
    end
  end

  all_tests_passed = true

ensure
  ##########################################################################################
  # Clean up all of the temp files created by this test.  It would be nice if this logic
  # could be handled outside of the test itself; I envision a stanza like this one appearing
  # in a very large number of the tests going forward unless it is handled by the framework.
  ##########################################################################################
  if all_tests_passed then
    all_hosts.each do |host|
      on(host, "rm -rf #{@host_test_tmp_dirs[host.name]}")
    end
  end
end