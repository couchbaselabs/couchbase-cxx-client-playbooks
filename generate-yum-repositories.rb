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

repo_http_base = "https://#{bucket}/clients/cxx/repos/rpm"
gpg = `which gpg 2>/dev/null`.strip

repos_dir = File.join(File.realpath(__dir__), "repos", "rpm")
FileUtils.rm_rf(repos_dir, verbose: true)
FileUtils.mkdir_p(repos_dir, verbose: true)

temp_dir = File.join(File.realpath(__dir__), "temp")
FileUtils.rm_rf(temp_dir, verbose: true)
FileUtils.mkdir_p(temp_dir, verbose: true)

def sh(*args)
  puts args.join(" ")
  system(*args) || abort($CHILD_STATUS.to_s)
end

Dir["*.compute.amazonaws.com/*.tar"].each do |bundle|
  distro, _, arch = File.basename(bundle).scan(/couchbase-cxx-client-.*\.((amzn|el|fc|suse.lp).*)\.(x86_64|aarch64).tar/).flatten
  distro_dir = File.join(repos_dir, distro, arch)
  FileUtils.mkdir_p(distro_dir, verbose: true)
  sh("gpg --export --armor #{gpg_key} > #{distro_dir}/RPM-GPG-KEY.txt")
  File.write(File.join(distro_dir, "couchbase-cxx-client.repo"), <<~END_OF_REPO)
    [couchbase-cxx-client]
    name = Couchbase C++SDK for #{distro} #{arch}
    baseurl = #{repo_http_base}/#{distro}/#{arch}
    gpgkey = #{repo_http_base}/#{distro}/#{arch}/RPM-GPG-KEY.txt
    gpgcheck = 1
    enabled = 1
  END_OF_REPO

  bundle_path = File.realpath(bundle)
  work_dir = File.join(temp_dir, distro, arch)
  FileUtils.rm_rf(work_dir, verbose: true)
  FileUtils.mkdir_p(work_dir, verbose: true)
  Dir.chdir(work_dir) do
    system("tar xf #{bundle_path}")
    Dir["*.rpm"].each do |package|
      package_path = File.join(distro_dir, package)
      FileUtils.cp(package, package_path, verbose: true)
      sh("rpm --addsign --define '__gpg #{gpg}' --define '_gpg_name #{gpg_key}' #{package_path}")
    end
  end
end

FileUtils.rm_rf(temp_dir, verbose: true)

Dir["#{repos_dir}/*/*"].each do |distro_dir|
  FileUtils.mkdir_p(distro_dir, verbose: true)
  sh("docker run --rm -v #{distro_dir}:/repo fedora:latest bash -c 'dnf install -y createrepo && createrepo /repo'")
  sh("gpg --detach-sign --armor --local-user #{gpg_key} #{distro_dir}/repodata/repomd.xml")
end
