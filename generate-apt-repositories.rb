#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "English"

# The script will use GnuPG command line tool to export it like this:
#  gpg --export --armor #{gpg_key}
gpg_key = "INSERT_YOUR_GPG_KEY_ID"
production_bucket = "packages.couchbase.com"
snapshots_bucket = "sdk-snapshots.couchbase.com"

bucket = ENV["COUCHBASE_CXX_CLIENT_UPLOAD_TO_PRODUCTION"] ? production_bucket : snapshots_bucket

repo_http_base = "https://#{bucket}/clients/cxx/repos/deb"
gpg = `which gpg 2>/dev/null`.strip

repos_dir = File.join(File.realpath(__dir__), "repos", "deb")
FileUtils.rm_rf(repos_dir, verbose: true)
FileUtils.mkdir_p(repos_dir, verbose: true)

temp_dir = File.join(File.realpath(__dir__), "temp")
FileUtils.rm_rf(temp_dir, verbose: true)
FileUtils.mkdir_p(temp_dir, verbose: true)

def sh(*args)
  puts args.join(" ")
  system(*args) || abort($CHILD_STATUS.to_s)
end

def deb_arch(arch)
  case arch
  when "x86_64"
    "amd64"
  when "aarch64"
    "arm64"
  end
end

Dir["*.compute.amazonaws.com/*.tar"].each do |bundle|
  distro, arch = File.basename(bundle).scan(/couchbase-cxx-client-.*\.(.*?)\.(x86_64|aarch64).tar/).flatten
  distro_dir = File.join(repos_dir, distro, arch)
  FileUtils.mkdir_p(distro_dir, verbose: true)
  sh("gpg --export --armor #{gpg_key} > #{distro_dir}/DEB-GPG-KEY.txt")
  File.write(File.join(distro_dir, "couchbase-cxx-client.sources"), <<~END_OF_REPO)
    Types: deb
    URIs: #{repo_http_base}/#{distro}/#{arch}
    Suites: #{distro}
    Components: #{distro}/main
    Signed-By: /usr/share/keyrings/couchbase-archive-keyring.gpg
    # Signed-By: #{gpg_key}
  END_OF_REPO

  FileUtils.mkdir_p(File.join(distro_dir, "conf"), verbose: true)
  File.write(File.join(distro_dir, "conf", "distributions"), <<~END_OF_CONF)
    Origin: couchbase
    SignWith: #{gpg_key}
    Suite: #{distro}
    Codename: #{distro}
    Version: #{distro}
    Components: #{distro}/main
    Architectures: #{deb_arch(arch)}
    Description: Couchbase C++SDK for #{distro} #{arch}
  END_OF_CONF

  bundle_path = File.realpath(bundle)
  work_dir = File.join(temp_dir, distro, arch)
  FileUtils.rm_rf(work_dir, verbose: true)
  FileUtils.mkdir_p(work_dir, verbose: true)
  Dir.chdir(work_dir) do
    system("tar xf #{bundle_path}")
    Dir["*.changes"].each do |package|
      next if package =~ /_source/

      sh("reprepro -v -v -T deb --ignore=wrongdistribution -b #{distro_dir} include #{distro} #{package}")
    end
  end
end

FileUtils.rm_rf(temp_dir, verbose: true)
