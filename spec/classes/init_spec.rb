# frozen_string_literal: true

require 'spec_helper'

describe 's3nd' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'without watchdog' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_class('s3nd::watchdog') }
        it { is_expected.not_to contain_systemd__timer('s3nd-watchdog.timer') }
      end

      context 'with watchdog' do
        let(:params) do
          {
            instances: {
              'sdfembs3-foo' => {
                'aws_access_key_id' => 'key',
                'aws_secret_access_key' => 'secret',
                'port' => 15_581,
                'env' => {
                  'S3ND_ENDPOINT_URL' => 'https://sdfembs3.sdf.slac.stanford.edu',
                },
              },
              'sdfembs3-bar' => {
                'aws_access_key_id' => 'key',
                'aws_secret_access_key' => 'secret',
                'port' => 15_591,
                'env' => {
                  'S3ND_ENDPOINT_URL' => 'https://sdfembs3.sdf.slac.stanford.edu/',
                },
              },
              'local' => {
                'aws_access_key_id' => 'key',
                'aws_secret_access_key' => 'secret',
                'port' => 15_571,
                'env' => {
                  'S3ND_ENDPOINT_URL' => 'https://s3.cp.lsst.org',
                },
              },
              'lookalike' => {
                'aws_access_key_id' => 'key',
                'aws_secret_access_key' => 'secret',
                'port' => 15_561,
                'env' => {
                  'S3ND_ENDPOINT_URL' => 'https://sdfembs3.sdf.slac.stanford.edu.example.com',
                },
              },
            },
            watchdog: {
              'endpoint_hostname' => 'sdfembs3.sdf.slac.stanford.edu',
              'receivers' => ['172.24.7.249', '172.24.7.250', '172.24.7.251'],
            },
          }
        end

        it { is_expected.to compile.with_all_deps }

        it 'pins the first receiver when no fact is present' do
          is_expected.to contain_host('sdfembs3.sdf.slac.stanford.edu').with(
            ensure: 'present',
            ip: '172.24.7.249'
          )
        end

        it 'derives the units of the instances targeting the endpoint' do
          is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with(
            ensure: 'file',
            mode: '0644',
            content: %r{^WATCHDOG_UNITS="s3nd-sdfembs3-bar\.service s3nd-sdfembs3-foo\.service"$}
          )
        end

        it do
          is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with(
            content: %r{^WATCHDOG_RECEIVERS="172\.24\.7\.249 172\.24\.7\.250 172\.24\.7\.251"$}
          )
        end

        it do
          is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with(
            content: %r{^WATCHDOG_FAIL_THRESHOLD="3"$}
          )
        end

        it do
          is_expected.to contain_file('/usr/local/sbin/s3nd-watchdog').with(
            ensure: 'file',
            mode: '0755',
            source: 'puppet:///modules/s3nd/s3nd-watchdog.sh'
          )
        end

        it do
          is_expected.to contain_systemd__timer('s3nd-watchdog.timer').with(
            ensure: 'present',
            active: true,
            enable: true,
            timer_content: %r{OnUnitActiveSec=30s}
          ).that_requires(
            [
              'File[/etc/sysconfig/s3nd-watchdog]',
              'File[/usr/local/sbin/s3nd-watchdog]',
            ]
          )
        end

        context 'with a fact reporting a known receiver' do
          let(:facts) do
            os_facts.merge('s3nd_watchdog' => { 'endpoint_ip' => '172.24.7.250' })
          end

          it 'pins the receiver chosen by the watchdog' do
            is_expected.to contain_host('sdfembs3.sdf.slac.stanford.edu').with(
              ip: '172.24.7.250'
            )
          end
        end

        context 'with a fact reporting an unknown ip' do
          let(:facts) do
            os_facts.merge('s3nd_watchdog' => { 'endpoint_ip' => '192.0.2.66' })
          end

          it 'falls back to the first receiver' do
            is_expected.to contain_host('sdfembs3.sdf.slac.stanford.edu').with(
              ip: '172.24.7.249'
            )
          end
        end

        context 'with an explicit units override' do
          let(:params) do
            super().merge(
              watchdog: super()[:watchdog].merge(
                'units' => ['s3nd-custom.service']
              )
            )
          end

          it do
            is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with(
              content: %r{^WATCHDOG_UNITS="s3nd-custom\.service"$}
            )
          end
        end

        context 'with the endpoint inherited from the class env' do
          let(:params) do
            super().merge(
              env: {
                'S3ND_ENDPOINT_URL' => 'https://sdfembs3.sdf.slac.stanford.edu',
              },
              instances: super()[:instances].merge(
                'inherits' => {
                  'aws_access_key_id' => 'key',
                  'aws_secret_access_key' => 'secret',
                  'port' => 15_551,
                }
              )
            )
          end

          it 'derives the units of all instances not overriding the endpoint' do
            is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with(
              content: %r{^WATCHDOG_UNITS="s3nd-inherits\.service s3nd-sdfembs3-bar\.service s3nd-sdfembs3-foo\.service"$}
            )
          end
        end

        context 'with ensure absent' do
          let(:params) do
            super().merge(
              watchdog: super()[:watchdog].merge('ensure' => 'absent')
            )
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with_ensure('absent') }
          it { is_expected.to contain_file('/usr/local/sbin/s3nd-watchdog').with_ensure('absent') }
          it { is_expected.to contain_systemd__timer('s3nd-watchdog.timer').with_ensure('absent') }
          it { is_expected.to contain_file('/etc/puppetlabs/facter/facts.d/s3nd_watchdog.json').with_ensure('absent') }
          it { is_expected.not_to contain_host('sdfembs3.sdf.slac.stanford.edu') }
        end

        context 'without any instances' do
          let(:params) do
            {
              watchdog: {
                'endpoint_hostname' => 'sdfembs3.sdf.slac.stanford.edu',
                'receivers' => ['172.24.7.249'],
              },
            }
          end

          it { is_expected.to compile.with_all_deps }

          it do
            is_expected.to contain_file('/etc/sysconfig/s3nd-watchdog').with(
              content: %r{^WATCHDOG_UNITS=""$}
            )
          end
        end
      end
    end
  end
end
