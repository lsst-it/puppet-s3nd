#
# @summary Client/server for pushing objects to S3 storage.
#
# @param instances
#   A hash of instances to configure. The key is the instance name and the value
#   is a hash of `s3nd::instance` parameters.
#
# @param image
#   The default container image to use for the instances. May be overridden by
#   the instance's env.
#
# @param volumes
#   An array of volumes to mount in the container. Uses the format
#   '/host:/contaner'. E.g. ['/home:/home', '/data:/data']
#   May be overridden by the instance.
#
# @param env
#  A hash of additional environment variables to set in the container, common
#  to all s3nd::instance(s) but may be overridden by the instance's env
#  param.
#
# @param watchdog
#   A hash of `s3nd::watchdog` class parameters. When set, deploys a watchdog
#   which health checks an /etc/hosts pinned endpoint and automatically fails
#   over to an alternate receiver, restarting the affected instances.
#
class s3nd (
  Optional[Hash[String[1], Hash]] $instances = undef,
  String[1] $image = 'ghcr.io/lsst-dm/s3nd:main',
  Array[Stdlib::Absolutepath] $volumes = ['/home:/home'],
  Hash $env = {},
  Optional[Hash[String[1], Any]] $watchdog = undef,
) {
  if $instances != undef {
    $instances.each |$name, $params| {
      s3nd::instance { $name:
        * => $params,
      }
    }
  }

  if $watchdog =~ NotUndef {
    class { 's3nd::watchdog':
      * => $watchdog,
    }
  }

  file { '/etc/sysconfig/s3nd':
    ensure  => directory,
    mode    => '0700',
    purge   => true,
    recurse => true,
    force   => true,
  }
}
