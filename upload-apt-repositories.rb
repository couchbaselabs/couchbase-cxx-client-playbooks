#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "English"

def sh(*args)
  puts args.join(" ")
  system(*args) || abort($CHILD_STATUS.to_s)
end

production_bucket = "packages.couchbase.com"
snapshots_bucket = "sdk-snapshots.couchbase.com"

bucket = ENV["COUCHBASE_CXX_CLIENT_UPLOAD_TO_PRODUCTION"] ? production_bucket : snapshots_bucket

cloudfront_distribution_ids = {
  production_bucket => "INSERT_PRODUCTION_CLOUDFRONT_DISTRIBUTION_ID",
  snapshots_bucket => "INSERT_STAGING_CLOUDFRONT_DISTRIBUTION_ID",
}

def deb_arch(arch)
  case arch
  when "x86_64"
    "amd64"
  when "aarch64"
    "arm64"
  end
end

patterns_to_invalidate = [
  "/clients/cxx/repos/%<distro>s/%<arch>s/conf/distributions",
  "/clients/cxx/repos/%<distro>s/%<arch>s/db/checksums.db",
  "/clients/cxx/repos/%<distro>s/%<arch>s/db/contents.cache.db",
  "/clients/cxx/repos/%<distro>s/%<arch>s/db/packages.db",
  "/clients/cxx/repos/%<distro>s/%<arch>s/db/references.db",
  "/clients/cxx/repos/%<distro>s/%<arch>s/db/release.caches.db",
  "/clients/cxx/repos/%<distro>s/%<arch>s/db/version",
  "/clients/cxx/repos/%<distro>s/%<arch>s/dists/%<distro>s/InRelease",
  "/clients/cxx/repos/%<distro>s/%<arch>s/dists/%<distro>s/Release",
  "/clients/cxx/repos/%<distro>s/%<arch>s/dists/%<distro>s/Release.gpg",
  "/clients/cxx/repos/%<distro>s/%<arch>s/dists/%<distro>s/%<distro>s/main/binary-%<deb_arch>s/Packages",
  "/clients/cxx/repos/%<distro>s/%<arch>s/dists/%<distro>s/%<distro>s/main/binary-%<deb_arch>s/Packages.gz",
  "/clients/cxx/repos/%<distro>s/%<arch>s/dists/%<distro>s/%<distro>s/main/binary-%<deb_arch>s/Release",
]

paths_to_invalidate = []
repo_files = []

repos_dir = File.join(File.realpath(__dir__), "repos", "deb")

Dir["#{repos_dir}/*/*"].each do |distro_dir|
  arch = File.basename(distro_dir)
  distro = File.basename(File.dirname(distro_dir))
  patterns_to_invalidate.each do |path|
    paths_to_invalidate << format(path, arch: arch, distro: distro, deb_arch: deb_arch(arch))
  end
  repo_files << "https://#{bucket}/clients/cxx/repos/deb/#{distro}/#{arch}/couchbase-cxx-client.sources"
end

sh("aws s3 sync --acl public-read --profile couchbase-prod #{repos_dir}/ s3://#{bucket}/clients/cxx/repos/deb/")
sh("aws cloudfront create-invalidation --no-cli-pager --profile couchbase-prod --distribution-id #{cloudfront_distribution_ids[bucket]} --paths #{paths_to_invalidate.join(' ')}")

puts <<~MESSAGE
  DEB Linux Distributions
  -----------------------

  ```
  apt update && apt install curl gpg
  ```

  ```
  DIST=noble  # also: jammy, bookworm
  ARCH=x86_64 # also: aarch64

  curl -L https://#{bucket}/clients/cxx/repos/deb/${DIST}/${ARCH}/DEB-GPG-KEY.txt | \\
    gpg --yes --dearmor -o /usr/share/keyrings/couchbase-archive-keyring.gpg

  curl -L -o/etc/apt/sources.list.d/couchbase-cxx-client.sources \\
    https://#{bucket}/clients/cxx/repos/deb/${DIST}/${ARCH}/couchbase-cxx-client.sources

  apt update
  apt install couchbase-cxx-client couchbase-cxx-client-dev couchbase-cxx-client-tools
  ```

  ```
  #{repo_files.uniq.sort.join("\n")}
  ```
MESSAGE
