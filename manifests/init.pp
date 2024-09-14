#
# @summary Client/server for pushing objects to S3 storage.
#
# @param instances
#   A hash of instances to configure. The key is the instance name and the value
#   is a hash of `s3daemon::instance` parameters.
#
class s3daemon (
  Optional[Hash[String[1], Hash]] $instances = undef
) {
  if $instances != undef {
    $instances.each |$name, $params| {
      s3daemon::instance { $name:
        * => $params,
      }
    }
  }
}
