#!/usr/bin/env rspec
require 'spec_helper'
require 'puppet/network/server'
require 'puppet/ssl/certificate_authority'
require 'socket'

describe Puppet::Network::Server, :unless => Puppet.features.microsoft_windows? do
  include PuppetSpec::Files

  # This reduces the odds of conflicting port numbers between concurrent runs
  # of the suite on the same machine dramatically.
  def port
    20000 + ($$ % 40000)
  end

  describe "when using webrick" do
    before :each do
      Puppet[:servertype] = 'webrick'
      Puppet[:server] = '127.0.0.1'
      @params = { :port => port, :handlers => [ :node ] }

      # Get a safe temporary file
      dir = tmpdir("webrick_integration_testing")

      Puppet.settings[:confdir] = dir
      Puppet.settings[:vardir] = dir
      Puppet.settings[:logdir] = dir
      Puppet.settings[:group] = Process.gid

      Puppet::SSL::Host.ca_location = :local

      ca = Puppet::SSL::CertificateAuthority.new
      ca.generate(Puppet[:certname]) unless Puppet::SSL::Certificate.indirection.find(Puppet[:certname])
    end

    after do
      Puppet.settings.clear

      Puppet::SSL::Host.ca_location = :none
    end

    describe "before listening" do
      it "should not be reachable at the specified address and port" do
        lambda { TCPSocket.new('127.0.0.1', port) }.should raise_error
      end
    end

    describe "when listening" do
      it "should be reachable on the specified address and port" do
        @server = Puppet::Network::Server.new(@params.merge(:port => port))
        @server.listen
        lambda { TCPSocket.new('127.0.0.1', port) }.should_not raise_error
      end

      it "should default to '0.0.0.0' as its bind address" do
        Puppet.settings.clear
        Puppet[:servertype] = 'webrick'
        Puppet[:bindaddress].should == '0.0.0.0'
      end

      it "should use any specified bind address" do
        Puppet[:bindaddress] = "127.0.0.1"
        @server = Puppet::Network::Server.new(@params.merge(:port => port))
        @server.stubs(:unlisten) # we're breaking listening internally, so we have to keep it from unlistening
        @server.send(:http_server).expects(:listen).with { |args| args[:address] == "127.0.0.1" }
        @server.listen
      end

      it "should not allow multiple servers to listen on the same address and port" do
        @server = Puppet::Network::Server.new(@params.merge(:port => port))
        @server.listen
        @server2 = Puppet::Network::Server.new(@params.merge(:port => port))
        lambda { @server2.listen }.should raise_error
      end

      after :each do
        @server.unlisten if @server && @server.listening?
      end
    end

    describe "after unlistening" do
      it "should not be reachable on the port and address assigned" do
        @server = Puppet::Network::Server.new(@params.merge(:port => port))
        @server.listen
        @server.unlisten
        lambda { TCPSocket.new('127.0.0.1', port) }.should raise_error(Errno::ECONNREFUSED)
      end
    end
  end
end
