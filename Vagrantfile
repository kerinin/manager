# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.define "server1" do |server1|
    server1.vm.hostname = "server1"
    server1.vm.box = "darron/consul"

    server1.vm.provider "virtualbox" do |v|
        v.customize [ "modifyvm", :id, "--cpus", "1" ]
        v.customize [ "modifyvm", :id, "--memory", "512" ]
    end

    server1.vm.network "private_network", ip: "192.168.2.2"

    config.vm.provision "shell", path: "spec/integration_scripts/master.sh"
  end

  # config.vm.define "server2", autostart: false do |server2|
  #   server2.vm.hostname = "server2"
  #   server2.vm.box = "darron/consul"

  #   server2.vm.provider "virtualbox" do |v|
  #       v.customize [ "modifyvm", :id, "--cpus", "1" ]
  #       v.customize [ "modifyvm", :id, "--memory", "512" ]
  #   end

  #   server2.vm.network "private_network", ip: "192.168.2.3"
  #   config.vm.provision "shell", path: "spec/integration_scripts/server1.sh"
  # end

  # config.vm.define "server3", autostart: false do |server3|
  #   server3.vm.hostname = "server3"
  #   server3.vm.box = "darron/consul"

  #   server3.vm.provider "virtualbox" do |v|
  #       v.customize [ "modifyvm", :id, "--cpus", "1" ]
  #       v.customize [ "modifyvm", :id, "--memory", "512" ]
  #   end

  #   server3.vm.network "private_network", ip: "192.168.2.4"
  #   config.vm.provision "shell", path: "spec/integration_scripts/server2.sh"
  # end

  config.vm.define "peer1" do |peer|
    peer.vm.hostname = "peer1"
    peer.vm.box = "darron/consul"

    peer.vm.provider "virtualbox" do |v|
        v.customize [ "modifyvm", :id, "--cpus", "1" ]
        v.customize [ "modifyvm", :id, "--memory", "512" ]
    end

    peer.vm.network "private_network", ip: "192.168.2.5"
    config.vm.provision "shell", path: "spec/integration_scripts/follower1.sh"
  end

  config.vm.define "peer2" do |peer|
    peer.vm.hostname = "peer2"
    peer.vm.box = "darron/consul"

    peer.vm.provider "virtualbox" do |v|
        v.customize [ "modifyvm", :id, "--cpus", "1" ]
        v.customize [ "modifyvm", :id, "--memory", "512" ]
    end

    peer.vm.network "private_network", ip: "192.168.2.6"
    config.vm.provision "shell", path: "spec/integration_scripts/follower2.sh"
  end

  config.vm.define "peer3" do |peer|
    peer.vm.hostname = "peer3"
    peer.vm.box = "darron/consul"

    peer.vm.provider "virtualbox" do |v|
        v.customize [ "modifyvm", :id, "--cpus", "1" ]
        v.customize [ "modifyvm", :id, "--memory", "512" ]
    end

    peer.vm.network "private_network", ip: "192.168.2.7"
    config.vm.provision "shell", path: "spec/integration_scripts/follower3.sh"
  end
end
