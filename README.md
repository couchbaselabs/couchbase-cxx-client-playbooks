# 0. Update credentials and sensitive variables

Get list by:

```
grep -Rni INSERT .
```

# 1. Launch instances

```
ansible-playbook launch-alpine-instances.yaml
ansible-playbook launch-rpm-instances.yaml
ansible-playbook launch-deb-instances.yaml
```

These steps will generate `hosts.ini` in the current directory. Do not forget
to remove/clean it before attempts, otherwise the playbooks might use
dead/extra instances.

# 2. Build the packages

```
ansible-playbook build-apks-on-ec2.yaml
ansible-playbook build-rpms-on-ec2.yaml
ansible-playbook build-debs-on-ec2.yaml
```

# 3. Generate repositories

```
ruby generate-apt-repositories.rb
ruby generate-yum-repositories.rb
```

```
COUCHBASE_CXX_CLIENT_UPLOAD_TO_PRODUCTION=yes ruby generate-apt-repositories.rb
COUCHBASE_CXX_CLIENT_UPLOAD_TO_PRODUCTION=yes ruby generate-yum-repositories.rb
```

# 4. Upload repositories

```
ruby upload-apt-repositories.rb
ruby upload-yum-repositories.rb
```

```
COUCHBASE_CXX_CLIENT_UPLOAD_TO_PRODUCTION=yes ruby upload-apt-repositories.rb
COUCHBASE_CXX_CLIENT_UPLOAD_TO_PRODUCTION=yes ruby upload-yum-repositories.rb
```

These scripts will print out snippets for the release notes with instructions for end users.
