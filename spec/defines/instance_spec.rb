# frozen_string_literal: true

require 'spec_helper'

describe 's3daemon::instance' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:title) { 'foo' }
      let(:params) do
        {
          s3_endpoint_url: 'https://s3.example.com',
          aws_access_key_id: 'foo',
          aws_secret_access_key: 'bar',
        }
      end

      it { is_expected.to compile.with_all_deps }

      it do
        is_expected.to contain_file("/etc/sysconfig/s3daemon-#{title}").with(
          ensure: 'file',
          show_diff: false,
          mode: '0600',
          content: %r{S3DAEMON_PORT=15556}
        )
      end

      it do
        is_expected.to contain_file("/etc/sysconfig/s3daemon-#{title}").
          that_notifies("Quadlets::Quadlet[s3daemon-#{title}.container]")
      end

      it do
        is_expected.to contain_quadlets__quadlet("s3daemon-#{title}.container").with(
          container_entry: {
            'EnvironmentFile' => ["/etc/sysconfig/s3daemon-#{title}"],
            'Image'           => 'ghcr.io/lsst-dm/s3daemon:main',
            'Network'         => 'host',
            'Volume'          => [
              '/home:/home',
              # '/data:/data',
            ],
            'User'            => 65_534,
            'Group'           => 65_534,
          }
        )
      end

      context 'with env' do
        let(:params) do
          super().merge(
            env: {
              'FOO' => 'BAR',
            }
          )
        end

        it do
          is_expected.to contain_file("/etc/sysconfig/s3daemon-#{title}").with(
            content: %r{FOO=BAR}
          )
        end
      end
    end
  end
end
