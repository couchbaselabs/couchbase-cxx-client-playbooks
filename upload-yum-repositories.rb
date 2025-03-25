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

patterns_to_invalidate = [
  "/clients/cxx/repos/%<distro>s/%<arch>s/repodata/repomd.xml",
  "/clients/cxx/repos/%<distro>s/%<arch>s/repodata/repomd.xml.asc",
]

paths_to_invalidate = []
repo_files = []

repos_dir = File.join(File.realpath(__dir__), "repos", "rpm")

Dir["#{repos_dir}/*/*"].each do |distro_dir|
  arch = File.basename(distro_dir)
  distro = File.basename(File.dirname(distro_dir))
  patterns_to_invalidate.each do |path|
    paths_to_invalidate << format(path, arch: arch, distro: distro)
  end
  repo_files << "https://#{bucket}/clients/cxx/repos/rpm/#{distro}/#{arch}/couchbase-cxx-client.repo"
end

sh("aws s3 sync --acl public-read --profile couchbase-prod #{repos_dir}/ s3://#{bucket}/clients/cxx/repos/rpm/")
sh("aws cloudfront create-invalidation --no-cli-pager --profile couchbase-prod --distribution-id #{cloudfront_distribution_ids[bucket]} --paths #{paths_to_invalidate.join(' ')}")

puts <<~MESSAGE
  RPM Linux Distributions
  -----------------------

  ```
  DIST=el9    # also: el8, amzn2023, fc40, fc41, suse.lp155
  ARCH=x86_64 # also: aarch64

  curl -L -o/etc/yum.repos.d/couchbase-cxx-client.repo \\
    https://packages.couchbase.com/clients/cxx/repos/rpm/${DIST}/${ARCH}/couchbase-cxx-client.repo

  dnf install couchbase-cxx-client couchbase-cxx-client-devel couchbase-cxx-client-tools
  ```

  ```
  #{repo_files.uniq.sort.join("\n")}
  ```
MESSAGE
