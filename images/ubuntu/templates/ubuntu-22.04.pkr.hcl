locals {
  managed_image_name = var.managed_image_name != "" ? var.managed_image_name : "packer-${var.image_os}-${var.image_version}"
}

variable "allowed_inbound_ip_addresses" {
  type    = list(string)
  default = []
}

variable "azure_tags" {
  type    = map(string)
  default = {}
}

variable "build_resource_group_name" {
  type    = string
  default = "${env("BUILD_RESOURCE_GROUP_NAME")}"
}

variable "managed_image_name" {
  type    = string
  default = ""
}

variable "client_id" {
  type    = string
  default = "${env("ARM_CLIENT_ID")}"
}

variable "client_secret" {
  type      = string
  default   = "${env("ARM_CLIENT_SECRET")}"
  sensitive = true
}

variable "client_cert_path" {
  type    = string
  default = "${env("ARM_CLIENT_CERT_PATH")}"
}

variable "commit_url" {
  type    = string
  default = ""
}

variable "dockerhub_login" {
  type    = string
  default = "${env("DOCKERHUB_LOGIN")}"
}

variable "dockerhub_password" {
  type    = string
  default = "${env("DOCKERHUB_PASSWORD")}"
}

variable "helper_script_folder" {
  type    = string
  default = "/imagegeneration/helpers"
}

variable "image_folder" {
  type    = string
  default = "/imagegeneration"
}

variable "image_os" {
  type    = string
  default = "ubuntu22"
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "imagedata_file" {
  type    = string
  default = "/imagegeneration/imagedata.json"
}

variable "installer_script_folder" {
  type    = string
  default = "/imagegeneration/installers"
}

variable "install_password" {
  type    = string
  default = ""
}

variable "location" {
  type    = string
  default = "${env("ARM_RESOURCE_LOCATION")}"
}

variable "private_virtual_network_with_public_ip" {
  type    = bool
  default = false
}

variable "managed_image_resource_group_name" {
  type    = string
  default = "${env("ARM_RESOURCE_GROUP")}"
}

variable "run_validation_diskspace" {
  type    = bool
  default = false
}

variable "subscription_id" {
  type    = string
  default = "${env("ARM_SUBSCRIPTION_ID")}"
}

variable "temp_resource_group_name" {
  type    = string
  default = "${env("TEMP_RESOURCE_GROUP_NAME")}"
}

variable "tenant_id" {
  type    = string
  default = "${env("ARM_TENANT_ID")}"
}

variable "virtual_network_name" {
  type    = string
  default = "${env("VNET_NAME")}"
}

variable "virtual_network_resource_group_name" {
  type    = string
  default = "${env("VNET_RESOURCE_GROUP")}"
}

variable "virtual_network_subnet_name" {
  type    = string
  default = "${env("VNET_SUBNET")}"
}

variable "vm_size" {
  type    = string
  default = "Standard_D4s_v4"
}

source "azure-arm" "build_image" {
  allowed_inbound_ip_addresses           = "${var.allowed_inbound_ip_addresses}"
  build_resource_group_name              = "${var.build_resource_group_name}"
  client_id                              = "${var.client_id}"
  client_secret                          = "${var.client_secret}"
  client_cert_path                       = "${var.client_cert_path}"
  image_offer                            = "0001-com-ubuntu-server-jammy"
  image_publisher                        = "canonical"
  image_sku                              = "22_04-lts"
  location                               = "${var.location}"
  os_disk_size_gb                        = "86"
  os_type                                = "Linux"
  private_virtual_network_with_public_ip = "${var.private_virtual_network_with_public_ip}"
  managed_image_name                     = "${local.managed_image_name}"
  managed_image_resource_group_name      = "${var.managed_image_resource_group_name}"
  subscription_id                        = "${var.subscription_id}"
  temp_resource_group_name               = "${var.temp_resource_group_name}"
  tenant_id                              = "${var.tenant_id}"
  virtual_network_name                   = "${var.virtual_network_name}"
  virtual_network_resource_group_name    = "${var.virtual_network_resource_group_name}"
  virtual_network_subnet_name            = "${var.virtual_network_subnet_name}"
  vm_size                                = "${var.vm_size}"

  dynamic "azure_tag" {
    for_each = var.azure_tags
    content {
      name = azure_tag.key
      value = azure_tag.value
    }
  }
}

variable "vm_template_name" {
  type    = string
  default = "ubuntu-22.04"
}

variable "ubuntu_iso_file" {
  type    = string
  default = "ubuntu-22.04.1-live-server-amd64.iso"
}

source "qemu" "custom_image" {

  http_directory = "cloud-init"
  #iso_url        = "https://releases.ubuntu.com/22.04.1/${var.ubuntu_iso_file}"
  #iso_checksum   = "file:https://releases.ubuntu.com/22.04.1/SHA256SUMS"
  iso_url      = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  iso_checksum = "file:https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS"
  disk_image   = true


  qemuargs = [
    ["-smbios",
      "type=1,serial=ds=nocloud-net;instance-id=packer;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    ]
  ]

  ssh_password = "ubuntu"
  ssh_username = "ubuntu"
  ssh_timeout  = "10m" # can be slow on CI

  headless         = true  # false # to see the process, In CI systems set to true
  accelerator      = "kvm" # set to none if no kvm installed
  format           = "qcow2"
  memory           = 4096
  disk_size        = "86G"
  cpus             = 16
  disk_compression = true
  disk_interface   = "virtio"
  # net_device       = "virtio-net"

  vm_name = "${var.vm_template_name}"
}


build {
  sources = ["source.qemu.custom_image"]
  provisioner "shell" {
    inline = ["while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 1; done"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mkdir ${var.image_folder}", "chmod 777 ${var.image_folder}"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/apt-mock.sh"
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/../scripts/build/repos.sh",
                        "${path.root}/../scripts/build/apt-ubuntu-archive.sh",
                        "${path.root}/../scripts/build/apt.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/limits.sh"
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/../scripts/helpers"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}"
    source      = "${path.root}/../scripts/build"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    sources     = [
      "${path.root}/../assets/post-gen",
      "${path.root}/../scripts/tests",
      "${path.root}/../scripts/docs-gen"
    ]
  }

  provisioner "file" {
    destination = "${var.image_folder}/docs-gen/"
    source      = "${path.root}/../../../helpers/software-report-base"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "${path.root}/../toolsets/toolset-2204.json"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = [
      "mv ${var.image_folder}/docs-gen ${var.image_folder}/SoftwareReport",
      "mv ${var.image_folder}/post-gen ${var.image_folder}/post-generation"
    ]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/preimagedata.sh"]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/apt-vital.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/complete-snap-setup.sh", "${path.root}/../scripts/build/powershellcore.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/Install-PowerShellModules.ps1", "${path.root}/../scripts/build/Install-AzureModules.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/../scripts/build/action-archive-cache.sh",
                        "${path.root}/../scripts/build/runner-package.sh",
                        "${path.root}/../scripts/build/apt-common.sh",
                        "${path.root}/../scripts/build/azcopy.sh",
                        "${path.root}/../scripts/build/azure-cli.sh",
                        "${path.root}/../scripts/build/azure-devops-cli.sh",
                        "${path.root}/../scripts/build/bicep.sh",
                        "${path.root}/../scripts/build/aliyun-cli.sh",
                        "${path.root}/../scripts/build/apache.sh",
                        "${path.root}/../scripts/build/aws.sh",
                        "${path.root}/../scripts/build/clang.sh",
                        "${path.root}/../scripts/build/swift.sh",
                        "${path.root}/../scripts/build/cmake.sh",
                        "${path.root}/../scripts/build/codeql-bundle.sh",
                        "${path.root}/../scripts/build/containers.sh",
                        "${path.root}/../scripts/build/dotnetcore-sdk.sh",
                        "${path.root}/../scripts/build/firefox.sh",
                        "${path.root}/../scripts/build/microsoft-edge.sh",
                        "${path.root}/../scripts/build/gcc.sh",
                        "${path.root}/../scripts/build/gfortran.sh",
                        "${path.root}/../scripts/build/git.sh",
                        "${path.root}/../scripts/build/git-lfs.sh",
                        "${path.root}/../scripts/build/github-cli.sh",
                        "${path.root}/../scripts/build/google-chrome.sh",
                        "${path.root}/../scripts/build/google-cloud-cli.sh",
                        "${path.root}/../scripts/build/haskell.sh",
                        "${path.root}/../scripts/build/heroku.sh",
                        "${path.root}/../scripts/build/java-tools.sh",
                        "${path.root}/../scripts/build/kubernetes-tools.sh",
                        "${path.root}/../scripts/build/oc.sh",
                        "${path.root}/../scripts/build/leiningen.sh",
                        "${path.root}/../scripts/build/miniconda.sh",
                        "${path.root}/../scripts/build/mono.sh",
                        "${path.root}/../scripts/build/kotlin.sh",
                        "${path.root}/../scripts/build/mysql.sh",
                        "${path.root}/../scripts/build/mssql-cmd-tools.sh",
                        "${path.root}/../scripts/build/sqlpackage.sh",
                        "${path.root}/../scripts/build/nginx.sh",
                        "${path.root}/../scripts/build/nvm.sh",
                        "${path.root}/../scripts/build/nodejs.sh",
                        "${path.root}/../scripts/build/bazel.sh",
                        "${path.root}/../scripts/build/oras-cli.sh",
                        "${path.root}/../scripts/build/php.sh",
                        "${path.root}/../scripts/build/postgresql.sh",
                        "${path.root}/../scripts/build/pulumi.sh",
                        "${path.root}/../scripts/build/ruby.sh",
                        "${path.root}/../scripts/build/r.sh",
                        "${path.root}/../scripts/build/rust.sh",
                        "${path.root}/../scripts/build/julia.sh",
                        "${path.root}/../scripts/build/sbt.sh",
                        "${path.root}/../scripts/build/selenium.sh",
                        "${path.root}/../scripts/build/terraform.sh",
                        "${path.root}/../scripts/build/packer.sh",
                        "${path.root}/../scripts/build/vcpkg.sh",
                        "${path.root}/../scripts/build/dpkg-config.sh",
                        "${path.root}/../scripts/build/yq.sh",
                        "${path.root}/../scripts/build/android.sh",
                        "${path.root}/../scripts/build/pypy.sh",
                        "${path.root}/../scripts/build/python.sh",
                        "${path.root}/../scripts/build/zstd.sh"
                        ]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DOCKERHUB_LOGIN=${var.dockerhub_login}", "DOCKERHUB_PASSWORD=${var.dockerhub_password}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/docker-compose.sh", "${path.root}/../scripts/build/docker.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/Install-Toolset.ps1", "${path.root}/../scripts/build/Configure-Toolset.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/pipx-packages.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/homebrew.sh"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/snap.sh"
  }

  provisioner "shell" {
    execute_command   = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    scripts           = ["${path.root}/../scripts/build/reboot.sh"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/../scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/apt-mock-remove.sh"
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/post-deployment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["RUN_VALIDATION=${var.run_validation_diskspace}"]
    scripts          = ["${path.root}/../scripts/build/validate-disk-space.sh"]
  }

  provisioner "file" {
    destination = "/tmp/"
    source      = "${path.root}/../assets/ubuntu2204.conf"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    remote_folder   = "/tmp"
    inline = [
      "/usr/bin/apt-get clean",
      "echo '* soft core unlimited' >> /etc/security/limits.conf",
      "echo '* hard core unlimited' >> /etc/security/limits.conf",
      "echo 'kernel.panic = 10' >> /etc/sysctl.conf",
      "rm -rf /etc/apparmor.d/cache/* /etc/apparmor.d/cache/.features /etc/netplan/50-cloud-init.yaml /etc/ssh/ssh_host* /etc/sudoers.d/90-cloud-init-users",
      "/usr/bin/truncate --size 0 /etc/machine-id",
      "/usr/bin/gawk -i inplace '/PasswordAuthentication/ { gsub(/yes/, \"no\") }; { print }' /etc/ssh/sshd_config",
      "rm -rf /root/.ssh",
      "rm -f /snap/README",
      "find /usr/share/netplan -name __pycache__ -exec rm -r {} +",
      "rm -rf /var/cache/pollinate/seeded /var/cache/snapd/* /var/cache/motd-news",
      "rm -rf /var/lib/cloud /var/lib/dbus/machine-id /var/lib/private /var/lib/systemd/timers /var/lib/systemd/timesync /var/lib/systemd/random-seed",
      "rm -f /var/lib/ubuntu-release-upgrader/release-upgrade-available",
      "rm -f /var/lib/update-notifier/fsck-at-reboot /var/lib/update-notifier/hwe-eol",
      "find /var/log -type f -exec rm {} +",
      "rm -rf /tmp/* /tmp/.*-unix /var/tmp/*",
      "rm -rf /home/packer",
      # "for i in group gshadow passwd shadow subuid subgid; do mv /etc/$i- /etc/$i; done",
      "/bin/sync",
      "/sbin/fstrim -v /",
    ]
  }



}
