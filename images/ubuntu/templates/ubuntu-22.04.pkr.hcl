packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

# install script wants paid docker account to avoid pull rate limit
variable "dockerhub_login" { # not required
  type    = string
  default = "${env("DOCKERHUB_LOGIN")}"
}

variable "dockerhub_password" { # not required
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

variable "vm_template_name" {
  type    = string
  default = "ubuntu-22.04"
}

variable "ubuntu_iso_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = "file:https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS"
}

variable "disk_image" { # 'true' tells packer it's not an iso, but a cloudimg bootable image
  type    = bool
  default = true
}

source "qemu" "custom_image" {

  http_directory = "cloud-init"
  iso_url      = var.ubuntu_iso_url
  iso_checksum = var.ubuntu_iso_checksum
  disk_image   = true


  qemuargs = [
    ["-smbios",
      "type=1,serial=ds=nocloud-net;instance-id=packer;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    ]
  ]

  ssh_password = "ubuntu"
  ssh_username = "ubuntu"
  ssh_timeout  = "10m" # can be slow on CI

  headless         = true  # true # to see the process, In CI systems set to true
  accelerator      = "hvf" # "kvm" # set to none if no kvm installed
  format           = "qcow2"
  memory           = 4096
  disk_size        = "86G"
  cpus             = 16
  disk_compression = true
  disk_interface   = "virtio"
  net_device       = "virtio-net"

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
    script          = "${path.root}/../scripts/build/configure-apt-mock.sh"
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "${path.root}/../scripts/build/install-ms-repos.sh",
      "${path.root}/../scripts/build/configure-apt-sources.sh",
      "${path.root}/../scripts/build/configure-apt.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/configure-limits.sh"
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
    scripts          = ["${path.root}/../scripts/build/configure-image-data.sh"]
  }

  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-apt-vital.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-powershell.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/Install-PowerShellModules.ps1", "${path.root}/../scripts/build/Install-PowerShellAzModules.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "${path.root}/../scripts/build/install-actions-cache.sh",
      "${path.root}/../scripts/build/install-runner-package.sh",
      "${path.root}/../scripts/build/install-apt-common.sh",
      "${path.root}/../scripts/build/install-azcopy.sh",
      "${path.root}/../scripts/build/install-azure-cli.sh",
      "${path.root}/../scripts/build/install-azure-devops-cli.sh",
      "${path.root}/../scripts/build/install-bicep.sh",
      "${path.root}/../scripts/build/install-aliyun-cli.sh",
      "${path.root}/../scripts/build/install-apache.sh",
      "${path.root}/../scripts/build/install-aws-tools.sh",
      "${path.root}/../scripts/build/install-clang.sh",
      "${path.root}/../scripts/build/install-swift.sh",
      "${path.root}/../scripts/build/install-cmake.sh",
      "${path.root}/../scripts/build/install-codeql-bundle.sh",
      "${path.root}/../scripts/build/install-container-tools.sh",
      "${path.root}/../scripts/build/install-dotnetcore-sdk.sh",
      "${path.root}/../scripts/build/install-firefox.sh",
      "${path.root}/../scripts/build/install-microsoft-edge.sh",
      "${path.root}/../scripts/build/install-gcc-compilers.sh",
      "${path.root}/../scripts/build/install-gfortran.sh",
      "${path.root}/../scripts/build/install-git.sh",
      "${path.root}/../scripts/build/install-git-lfs.sh",
      "${path.root}/../scripts/build/install-github-cli.sh",
      "${path.root}/../scripts/build/install-google-chrome.sh",
      "${path.root}/../scripts/build/install-google-cloud-cli.sh",
      "${path.root}/../scripts/build/install-haskell.sh",
      "${path.root}/../scripts/build/install-heroku.sh",
      "${path.root}/../scripts/build/install-java-tools.sh",
      "${path.root}/../scripts/build/install-kubernetes-tools.sh",
      "${path.root}/../scripts/build/install-oc-cli.sh",
      "${path.root}/../scripts/build/install-leiningen.sh",
      "${path.root}/../scripts/build/install-miniconda.sh",
      "${path.root}/../scripts/build/install-mono.sh",
      "${path.root}/../scripts/build/install-kotlin.sh",
      "${path.root}/../scripts/build/install-mysql.sh",
      "${path.root}/../scripts/build/install-mssql-tools.sh",
      "${path.root}/../scripts/build/install-sqlpackage.sh",
      "${path.root}/../scripts/build/install-nginx.sh",
      "${path.root}/../scripts/build/install-nvm.sh",
      "${path.root}/../scripts/build/install-nodejs.sh",
      "${path.root}/../scripts/build/install-bazel.sh",
      "${path.root}/../scripts/build/install-oras-cli.sh",
      "${path.root}/../scripts/build/install-php.sh",
      "${path.root}/../scripts/build/install-postgresql.sh",
      "${path.root}/../scripts/build/install-pulumi.sh",
      "${path.root}/../scripts/build/install-ruby.sh",
      "${path.root}/../scripts/build/install-rlang.sh",
      "${path.root}/../scripts/build/install-rust.sh",
      "${path.root}/../scripts/build/install-julia.sh",
      "${path.root}/../scripts/build/install-sbt.sh",
      "${path.root}/../scripts/build/install-selenium.sh",
      "${path.root}/../scripts/build/install-terraform.sh",
      "${path.root}/../scripts/build/install-packer.sh",
      "${path.root}/../scripts/build/install-vcpkg.sh",
      "${path.root}/../scripts/build/configure-dpkg.sh",
      "${path.root}/../scripts/build/install-yq.sh",
      "${path.root}/../scripts/build/install-android-sdk.sh",
      "${path.root}/../scripts/build/install-pypy.sh",
      "${path.root}/../scripts/build/install-python.sh",
      "${path.root}/../scripts/build/install-zstd.sh"
    ]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DOCKERHUB_LOGIN=${var.dockerhub_login}", "DOCKERHUB_PASSWORD=${var.dockerhub_password}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-docker.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/Install-Toolset.ps1", "${path.root}/../scripts/build/Configure-Toolset.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-pipx-packages.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-homebrew.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-snap.sh"]
  }

  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    inline            = ["echo 'Reboot VM'", "sudo reboot"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/../scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-system.sh"]
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
