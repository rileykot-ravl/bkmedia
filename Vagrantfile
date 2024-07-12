# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|

  config.vm.define "web" do |web|
    web.vm.box = "hashicorp/bionic64"
    # custom ip to ssh into the vm
    web.vm.network "private_network", ip: "192.168.33.10"
    web.vm.hostname = "web"
  end

  config.vm.define "host" do |host|
    host.vm.box = "hashicorp/bionic64"
    # custom ip to ssh into the vm
    host.vm.network "private_network", ip: "192.168.33.11"
    host.vm.hostname = "host"
  end


  #config.vm.box = "hashicorp/bionic64"
end
