#!/usr/bin/env rspec
require 'spec_helper'
require 'puppet_spec/files'
require 'puppet_spec/modules'
require 'puppet/module_tool/checksums'

describe Puppet::Module do
  include PuppetSpec::Files

  before do
    # This is necessary because of the extra checks we have for the deprecated
    # 'plugins' directory
    FileTest.stubs(:exist?).returns false
  end

  it "should have a class method that returns a named module from a given environment" do
    env = mock 'module'
    env.expects(:module).with("mymod").returns "yep"
    Puppet::Node::Environment.expects(:new).with("myenv").returns env

    Puppet::Module.find("mymod", "myenv").should == "yep"
  end

  it "should return nil if asked for a named module that doesn't exist" do
    env = mock 'module'
    env.expects(:module).with("mymod").returns nil
    Puppet::Node::Environment.expects(:new).with("myenv").returns env

    Puppet::Module.find("mymod", "myenv").should be_nil
  end

  it "should support a 'version' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.version = 1.09
    mod.version.should == 1.09
  end

  it "should support a 'source' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.source = "http://foo/bar"
    mod.source.should == "http://foo/bar"
  end

  it "should support a 'project_page' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.project_page = "http://foo/bar"
    mod.project_page.should == "http://foo/bar"
  end

  it "should support an 'author' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.author = "Luke Kanies <luke@madstop.com>"
    mod.author.should == "Luke Kanies <luke@madstop.com>"
  end

  it "should support a 'license' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.license = "GPL2"
    mod.license.should == "GPL2"
  end

  it "should support a 'summary' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.summary = "GPL2"
    mod.summary.should == "GPL2"
  end

  it "should support a 'description' attribute" do
    mod = Puppet::Module.new("mymod")
    mod.description = "GPL2"
    mod.description.should == "GPL2"
  end

  it "should support specifying a compatible puppet version" do
    mod = Puppet::Module.new("mymod")
    mod.puppetversion = "0.25"
    mod.puppetversion.should == "0.25"
  end

  it "should validate that the puppet version is compatible" do
    mod = Puppet::Module.new("mymod")
    mod.puppetversion = "0.25"
    Puppet.expects(:version).returns "0.25"
    mod.validate_puppet_version
  end

  it "should fail if the specified puppet version is not compatible" do
    mod = Puppet::Module.new("mymod")
    mod.puppetversion = "0.25"
    Puppet.stubs(:version).returns "0.24"
    lambda { mod.validate_puppet_version }.should raise_error(Puppet::Module::IncompatibleModule)
  end

  describe "when finding unmet dependencies" do
    before do
      FileTest.unstub(:exist?)
      @modpath = tmpdir('modpath')
      Puppet.settings[:modulepath] = @modpath
    end

    it "should list modules that are missing" do
      mod = PuppetSpec::Modules.create(
        'needy',
        @modpath,
        :metadata => {
          :dependencies => [{
            "version_requirement" => ">= 2.2.0",
            "name" => "baz/foobar"
          }]
        }
      )
      mod.unmet_dependencies.should == [{
        :reason => :missing,
        :name   => "baz/foobar",
        :version_constraint => ">= 2.2.0",
        :parent => { :name => 'puppetlabs/needy', :version => 'v9.9.9' },
        :mod_details => { :installed_version => nil }
      }]
    end

    it "should list modules that are missing and have invalid names" do
      mod = PuppetSpec::Modules.create(
        'needy',
        @modpath,
        :metadata => {
          :dependencies => [{
            "version_requirement" => ">= 2.2.0",
            "name" => "baz/foobar=bar"
          }]
        }
      )
      mod.unmet_dependencies.should == [{
        :reason => :missing,
        :name   => "baz/foobar=bar",
        :version_constraint => ">= 2.2.0",
        :parent => { :name => 'puppetlabs/needy', :version => 'v9.9.9' },
        :mod_details => { :installed_version => nil }
      }]
    end

    it "should list modules with unmet version requirement" do
      mod = PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => {
          :dependencies => [{
            "version_requirement" => ">= 2.2.0",
            "name" => "baz/foobar"
          }]
        }
      )
      mod2 = PuppetSpec::Modules.create(
        'foobaz',
        @modpath,
        :metadata => {
          :dependencies => [{
            "version_requirement" => "1.0.0",
            "name" => "baz/foobar"
          }]
        }
      )

      PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => { :version => '2.0.0', :author  => 'baz' }
      )

      mod.unmet_dependencies.should == [{
        :reason => :version_mismatch,
        :name   => "baz/foobar",
        :version_constraint => ">= 2.2.0",
        :parent => { :version => "v9.9.9", :name => "puppetlabs/foobar" },
        :mod_details => { :installed_version => "2.0.0" }
      }]

      mod2.unmet_dependencies.should == [{
        :reason => :version_mismatch,
        :name   => "baz/foobar",
        :version_constraint => "v1.0.0",
        :parent => { :version => "v9.9.9", :name => "puppetlabs/foobaz" },
        :mod_details => { :installed_version => "2.0.0" }
      }]

    end

    it "should consider a dependency without a version requirement to be satisfied" do
      mod = PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => {
          :dependencies => [{
            "name" => "baz/foobar"
          }]
        }
      )
      PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => {
          :version => '2.0.0',
          :author  => 'baz'
        }
      )

      mod.unmet_dependencies.should be_empty
    end

    it "should consider a dependency without a semantic version to be unmet" do
      mod = PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => {
          :dependencies => [{
            "name" => "baz/foobar"
          }]
        }
      )
      PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => {
          :version => '5.1',
          :author  => 'baz'
        }
      )

      mod.unmet_dependencies.should == [{
        :reason => :non_semantic_version,
        :parent => { :version => "v9.9.9", :name => "puppetlabs/foobar" },
        :mod_details => { :installed_version => "5.1" },
        :name => "baz/foobar",
        :version_constraint => ">= 0.0.0"
      }]
    end

    it "should have valid dependencies when no dependencies have been specified" do
      mod = PuppetSpec::Modules.create(
        'foobar',
        @modpath,
        :metadata => {
          :dependencies => []
        }
      )

      mod.unmet_dependencies.should == []
    end

    it "should only list unmet dependencies" do
      mod = PuppetSpec::Modules.create(
        'mymod',
        @modpath,
        :metadata => {
          :dependencies => [
            {
              "version_requirement" => ">= 2.2.0",
              "name" => "baz/satisfied"
            },
            {
              "version_requirement" => ">= 2.2.0",
              "name" => "baz/notsatisfied"
            }
          ]
        }
      )
      PuppetSpec::Modules.create(
        'satisfied',
        @modpath,
        :metadata => {
          :version => '3.3.0',
          :author  => 'baz'
        }
      )

      mod.unmet_dependencies.should == [{
        :reason => :missing,
        :mod_details => { :installed_version => nil },
        :parent => { :version => "v9.9.9", :name => "puppetlabs/mymod" },
        :name => "baz/notsatisfied",
        :version_constraint => ">= 2.2.0"
      }]
    end

    it "should be empty when all dependencies are met" do
      mod = PuppetSpec::Modules.create(
        'mymod2',
        @modpath,
        :metadata => {
          :dependencies => [
            {
              "version_requirement" => ">= 2.2.0",
              "name" => "baz/satisfied"
            },
            {
              "version_requirement" => "< 2.2.0",
              "name" => "baz/alsosatisfied"
            }
          ]
        }
      )
      PuppetSpec::Modules.create(
        'satisfied',
        @modpath,
        :metadata => {
          :version => '3.3.0',
          :author  => 'baz'
        }
      )
      PuppetSpec::Modules.create(
        'alsosatisfied',
        @modpath,
        :metadata => {
          :version => '2.1.0',
          :author  => 'baz'
        }
      )

      mod.unmet_dependencies.should be_empty
    end
  end

  describe "when managing supported platforms" do
    it "should support specifying a supported platform" do
      mod = Puppet::Module.new("mymod")
      mod.supports "solaris"
    end

    it "should support specifying a supported platform and version" do
      mod = Puppet::Module.new("mymod")
      mod.supports "solaris", 1.0
    end

    it "should fail when not running on a supported platform" do
      pending "Not sure how to send client platform to the module"
      mod = Puppet::Module.new("mymod")
      Facter.expects(:value).with("operatingsystem").returns "Solaris"

      mod.supports "hpux"

      lambda { mod.validate_supported_platform }.should raise_error(Puppet::Module::UnsupportedPlatform)
    end

    it "should fail when supported platforms are present but of the wrong version" do
      pending "Not sure how to send client platform to the module"
      mod = Puppet::Module.new("mymod")
      Facter.expects(:value).with("operatingsystem").returns "Solaris"
      Facter.expects(:value).with("operatingsystemrelease").returns 2.0

      mod.supports "Solaris", 1.0

      lambda { mod.validate_supported_platform }.should raise_error(Puppet::Module::IncompatiblePlatform)
    end

    it "should be considered supported when no supported platforms have been specified" do
      pending "Not sure how to send client platform to the module"
      mod = Puppet::Module.new("mymod")
      lambda { mod.validate_supported_platform }.should_not raise_error
    end

    it "should be considered supported when running on a supported platform" do
      pending "Not sure how to send client platform to the module"
      mod = Puppet::Module.new("mymod")
      Facter.expects(:value).with("operatingsystem").returns "Solaris"
      Facter.expects(:value).with("operatingsystemrelease").returns 2.0

      mod.supports "Solaris", 1.0

      lambda { mod.validate_supported_platform }.should raise_error(Puppet::Module::IncompatiblePlatform)
    end

    it "should be considered supported when running on any of multiple supported platforms" do
      pending "Not sure how to send client platform to the module"
    end

    it "should validate its platform support on initialization" do
      pending "Not sure how to send client platform to the module"
    end
  end

  it "should return nil if asked for a module whose name is 'nil'" do
    Puppet::Module.find(nil, "myenv").should be_nil
  end

  it "should provide support for logging" do
    Puppet::Module.ancestors.should be_include(Puppet::Util::Logging)
  end

  it "should be able to be converted to a string" do
    Puppet::Module.new("foo").to_s.should == "Module foo"
  end

  it "should add the path to its string form if the module is found" do
    mod = Puppet::Module.new("foo")
    mod.stubs(:path).returns "/a"
    mod.to_s.should == "Module foo(/a)"
  end

  it "should fail if its name is not alphanumeric" do
    lambda { Puppet::Module.new(".something") }.should raise_error(Puppet::Module::InvalidName)
  end

  it "should require a name at initialization" do
    lambda { Puppet::Module.new }.should raise_error(ArgumentError)
  end

  it "should convert an environment name into an Environment instance" do
    Puppet::Module.new("foo", :environment => "prod").environment.should be_instance_of(Puppet::Node::Environment)
  end

  it "should accept an environment at initialization" do
    Puppet::Module.new("foo", :environment => :prod).environment.name.should == :prod
  end

  it "should use the default environment if none is provided" do
    env = Puppet::Node::Environment.new
    Puppet::Module.new("foo").environment.should equal(env)
  end

  it "should use any provided Environment instance" do
    env = Puppet::Node::Environment.new
    Puppet::Module.new("foo", :environment => env).environment.should equal(env)
  end

  describe ".path" do
    before do
      dir = tmpdir("deep_path")

      @first = File.join(dir, "first")
      @second = File.join(dir, "second")
      Puppet[:modulepath] = "#{@first}#{File::PATH_SEPARATOR}#{@second}"

      FileUtils.mkdir_p(@first)
      FileUtils.mkdir_p(@second)
    end

    it "should return the path to the first found instance in its environment's module paths as its path" do
      modpath = File.join(@first, "foo")
      FileUtils.mkdir_p(modpath)

      # Make a second one, which we shouldn't find
      FileUtils.mkdir_p(File.join(@second, "foo"))

      mod = Puppet::Module.new("foo")
      mod.path.should == modpath
    end

    it "should be able to find itself in a directory other than the first directory in the module path" do
      modpath = File.join(@second, "foo")
      FileUtils.mkdir_p(modpath)

      mod = Puppet::Module.new("foo")
      mod.should be_exist
      mod.path.should == modpath
    end

    it "should be able to find itself in a directory other than the first directory in the module path even when it exists in the first" do
      environment = Puppet::Node::Environment.new

      first_modpath = File.join(@first, "foo")
      FileUtils.mkdir_p(first_modpath)
      second_modpath = File.join(@second, "foo")
      FileUtils.mkdir_p(second_modpath)

      mod = Puppet::Module.new("foo", :environment => environment, :path => second_modpath)
      mod.path.should == File.join(@second, "foo")
      mod.environment.should == environment
    end
  end

  describe '#modulepath' do
    it "should return the directory the module is installed in, if a path exists" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns "/a/foo"
      mod.modulepath.should == '/a'
    end

    it "should return nil if no path exists" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns nil
      mod.modulepath.should be_nil
    end
  end

  it "should be considered existent if it exists in at least one module path" do
    mod = Puppet::Module.new("foo")
    mod.expects(:path).returns "/a/foo"
    mod.should be_exist
  end

  it "should be considered nonexistent if it does not exist in any of the module paths" do
    mod = Puppet::Module.new("foo")
    mod.expects(:path).returns nil
    mod.should_not be_exist
  end

  [:plugins, :templates, :files, :manifests].each do |filetype|
    dirname = filetype == :plugins ? "lib" : filetype.to_s
    it "should be able to return individual #{filetype}" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns "/a/foo"
      path = File.join("/a/foo", dirname, "my/file")
      FileTest.expects(:exist?).with(path).returns true
      mod.send(filetype.to_s.sub(/s$/, ''), "my/file").should == path
    end

    it "should consider #{filetype} to be present if their base directory exists" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns "/a/foo"
      path = File.join("/a/foo", dirname)
      FileTest.expects(:exist?).with(path).returns true
      mod.send(filetype.to_s + "?").should be_true
    end

    it "should consider #{filetype} to be absent if their base directory does not exist" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns "/a/foo"
      path = File.join("/a/foo", dirname)
      FileTest.expects(:exist?).with(path).returns false
      mod.send(filetype.to_s + "?").should be_false
    end

    it "should consider #{filetype} to be absent if the module base directory does not exist" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns nil
      mod.send(filetype.to_s + "?").should be_false
    end

    it "should return nil if asked to return individual #{filetype} that don't exist" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns "/a/foo"
      path = File.join("/a/foo", dirname, "my/file")
      FileTest.expects(:exist?).with(path).returns false
      mod.send(filetype.to_s.sub(/s$/, ''), "my/file").should be_nil
    end

    it "should return nil when asked for individual #{filetype} if the module does not exist" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns nil
      mod.send(filetype.to_s.sub(/s$/, ''), "my/file").should be_nil
    end

    it "should return the base directory if asked for a nil path" do
      mod = Puppet::Module.new("foo")
      mod.stubs(:path).returns "/a/foo"
      base = File.join("/a/foo", dirname)
      FileTest.expects(:exist?).with(base).returns true
      mod.send(filetype.to_s.sub(/s$/, ''), nil).should == base
    end
  end

  it "should return the path to the plugin directory" do
    mod = Puppet::Module.new("foo")
    mod.stubs(:path).returns "/a/foo"

    mod.plugin_directory.should == "/a/foo/lib"
  end

  it "should throw a warning if plugins are in a 'plugins' directory rather than a 'lib' directory" do
    mod = Puppet::Module.new("foo")
    mod.stubs(:path).returns "/a/foo"
    FileTest.expects(:exist?).with("/a/foo/plugins").returns true
    Puppet.expects(:deprecation_warning).with("using the deprecated 'plugins' directory for ruby extensions; please move to 'lib'")

    mod.plugin_directory.should == "/a/foo/plugins"
  end

  it "should default to 'lib' for the plugins directory" do
    mod = Puppet::Module.new("foo")
    mod.stubs(:path).returns "/a/foo"
    mod.plugin_directory.should == "/a/foo/lib"
  end
end

describe Puppet::Module, "when finding matching manifests" do
  before do
    @mod = Puppet::Module.new("mymod")
    @mod.stubs(:path).returns "/a"
    @pq_glob_with_extension = "yay/*.xx"
    @fq_glob_with_extension = "/a/manifests/#{@pq_glob_with_extension}"
  end

  it "should return all manifests matching the glob pattern" do
    Dir.expects(:glob).with(@fq_glob_with_extension).returns(%w{foo bar})
    FileTest.stubs(:directory?).returns false

    @mod.match_manifests(@pq_glob_with_extension).should == %w{foo bar}
  end

  it "should not return directories" do
    Dir.expects(:glob).with(@fq_glob_with_extension).returns(%w{foo bar})

    FileTest.expects(:directory?).with("foo").returns false
    FileTest.expects(:directory?).with("bar").returns true
    @mod.match_manifests(@pq_glob_with_extension).should == %w{foo}
  end

  it "should default to the 'init' file if no glob pattern is specified" do
    Dir.expects(:glob).with("/a/manifests/init.{pp,rb}").returns(%w{/a/manifests/init.pp})

    @mod.match_manifests(nil).should == %w{/a/manifests/init.pp}
  end

  it "should return all manifests matching the glob pattern in all existing paths" do
    Dir.expects(:glob).with(@fq_glob_with_extension).returns(%w{a b})

    @mod.match_manifests(@pq_glob_with_extension).should == %w{a b}
  end

  it "should match the glob pattern plus '.{pp,rb}' if no extention is specified" do
    Dir.expects(:glob).with("/a/manifests/yay/foo.{pp,rb}").returns(%w{yay})

    @mod.match_manifests("yay/foo").should == %w{yay}
  end

  it "should return an empty array if no manifests matched" do
    Dir.expects(:glob).with(@fq_glob_with_extension).returns([])

    @mod.match_manifests(@pq_glob_with_extension).should == []
  end
end

describe Puppet::Module do
  include PuppetSpec::Files
  before do
    @modpath = tmpdir('modpath')
    @module = PuppetSpec::Modules.create('mymod', @modpath)
  end

  it "should use 'License' in its current path as its metadata file" do
    @module.license_file.should == "#{@modpath}/mymod/License"
  end

  it "should return nil as its license file when the module has no path" do
    Puppet::Module.any_instance.stubs(:path).returns nil
    Puppet::Module.new("foo").license_file.should be_nil
  end

  it "should cache the license file" do
    @module.expects(:path).once.returns nil
    @module.license_file
    @module.license_file
  end

  it "should use 'metadata.json' in its current path as its metadata file" do
    @module.metadata_file.should == "#{@modpath}/mymod/metadata.json"
  end

  it "should return nil as its metadata file when the module has no path" do
    Puppet::Module.any_instance.stubs(:path).returns nil
    Puppet::Module.new("foo").metadata_file.should be_nil
  end

  it "should cache the metadata file" do
    Puppet::Module.any_instance.expects(:path).once.returns nil
    mod = Puppet::Module.new("foo")
    mod.metadata_file.should == mod.metadata_file
  end

  it "should have metadata if it has a metadata file and its data is not empty" do
    FileTest.expects(:exist?).with(@module.metadata_file).returns true
    File.stubs(:read).with(@module.metadata_file).returns "{\"foo\" : \"bar\"}"

    @module.should be_has_metadata
  end

  it "should have metadata if it has a metadata file and its data is not empty" do
    FileTest.expects(:exist?).with(@module.metadata_file).returns true
    File.stubs(:read).with(@module.metadata_file).returns "{\"foo\" : \"bar\"}"

    @module.should be_has_metadata
  end

  it "should not have metadata if has a metadata file and its data is empty" do
    FileTest.expects(:exist?).with(@module.metadata_file).returns true
    File.stubs(:read).with(@module.metadata_file).returns "/*
+-----------------------------------------------------------------------+
|                                                                       |
|                    ==> DO NOT EDIT THIS FILE! <==                     |
|                                                                       |
|   You should edit the `Modulefile` and run `puppet-module build`      |
|   to generate the `metadata.json` file for your releases.             |
|                                                                       |
+-----------------------------------------------------------------------+
*/

{}"

    @module.should_not be_has_metadata
  end

  it "should know if it is missing a metadata file" do
    FileTest.expects(:exist?).with(@module.metadata_file).returns false

    @module.should_not be_has_metadata
  end

  it "should be able to parse its metadata file" do
    @module.should respond_to(:load_metadata)
  end

  it "should parse its metadata file on initialization if it is present" do
    Puppet::Module.any_instance.expects(:has_metadata?).returns true
    Puppet::Module.any_instance.expects(:load_metadata)

    Puppet::Module.new("yay")
  end

  describe "when loading the metadata file", :if => Puppet.features.pson? do
    before do
      @data = {
        :license       => "GPL2",
        :author        => "luke",
        :version       => "1.0",
        :source        => "http://foo/",
        :puppetversion => "0.25",
        :dependencies  => []
      }
      @text = @data.to_pson

      @module = Puppet::Module.new("foo")
      @module.stubs(:metadata_file).returns "/my/file"
      File.stubs(:read).with("/my/file").returns @text
    end

    %w{source author version license}.each do |attr|
      it "should set #{attr} if present in the metadata file" do
        @module.load_metadata
        @module.send(attr).should == @data[attr.to_sym]
      end

      it "should fail if #{attr} is not present in the metadata file" do
        @data.delete(attr.to_sym)
        @text = @data.to_pson
        File.stubs(:read).with("/my/file").returns @text
        lambda { @module.load_metadata }.should raise_error(
          Puppet::Module::MissingMetadata,
          "No #{attr} module metadata provided for foo"
        )
      end
    end

    it "should set puppetversion if present in the metadata file" do
      @module.load_metadata
      @module.puppetversion.should == @data[:puppetversion]
    end

    context "when versionRequirement is used for dependency version info" do
      before do
        @data = {
          :license       => "GPL2",
          :author        => "luke",
          :version       => "1.0",
          :source        => "http://foo/",
          :puppetversion => "0.25",
          :dependencies  => [
            {
              "versionRequirement" => "0.0.1",
              "name" => "pmtacceptance/stdlib"
            },
            {
              "versionRequirement" => "0.1.0",
              "name" => "pmtacceptance/apache"
            }
          ]
        }
        @text = @data.to_pson

        @module = Puppet::Module.new("foo")
        @module.stubs(:metadata_file).returns "/my/file"
        File.stubs(:read).with("/my/file").returns @text
      end

      it "should set the dependency version_requirement key" do
        @module.load_metadata
        @module.dependencies[0]['version_requirement'].should == "0.0.1"
      end

      it "should set the version_requirement key for all dependencies" do
        @module.load_metadata
        @module.dependencies[0]['version_requirement'].should == "0.0.1"
        @module.dependencies[1]['version_requirement'].should == "0.1.0"
      end
    end

    it "should fail if the discovered name is different than the metadata name"
  end

  it "should be able to tell if there are local changes" do
    pending("porting to Windows", :if => Puppet.features.microsoft_windows?) do
      modpath = tmpdir('modpath')
      foo_checksum = 'acbd18db4cc2f85cedef654fccc4a4d8'
      checksummed_module = PuppetSpec::Modules.create(
        'changed',
        modpath,
        :metadata => {
          :checksums => {
            "foo" => foo_checksum,
          }
        }
      )

      foo_path = Pathname.new(File.join(checksummed_module.path, 'foo'))

      IO.binwrite(foo_path, 'notfoo')
      Puppet::ModuleTool::Checksums.new(foo_path).checksum(foo_path).should_not == foo_checksum
      checksummed_module.has_local_changes?.should be_true

      IO.binwrite(foo_path, 'foo')

      Puppet::ModuleTool::Checksums.new(foo_path).checksum(foo_path).should == foo_checksum
      checksummed_module.has_local_changes?.should be_false
    end
  end

  it "should know what other modules require it" do
    Puppet.settings[:modulepath] = @modpath
    dependable = PuppetSpec::Modules.create(
      'dependable',
      @modpath,
      :metadata => {:author => 'puppetlabs'}
    )
    PuppetSpec::Modules.create(
      'needy',
      @modpath,
      :metadata => {
        :author => 'beggar',
        :dependencies => [{
            "version_requirement" => ">= 2.2.0",
            "name" => "puppetlabs/dependable"
        }]
      }
    )
    PuppetSpec::Modules.create(
      'wantit',
      @modpath,
      :metadata => {
        :author => 'spoiled',
        :dependencies => [{
            "version_requirement" => "< 5.0.0",
            "name" => "puppetlabs/dependable"
        }]
      }
    )
    dependable.required_by.should =~ [
      {
        "name"    => "beggar/needy",
        "version" => "9.9.9",
        "version_requirement" => ">= 2.2.0"
      },
      {
        "name"    => "spoiled/wantit",
        "version" => "9.9.9",
        "version_requirement" => "< 5.0.0"
      }
    ]
  end
end
