# @summary
#   Deploy the s3nd service
#
# @param aws_access_key_id
#   The AWS access key ID to use for authentication.
#
# @param aws_secret_access_key
#   The AWS secret access key to use for authentication.
#
# @param image
#   The container image to use for the s3nd service.
#
# @param volumes
#   An array of volumes to mount in the container. Uses the format
#   '/host:/contaner'.  E.g. ['/home:/home', '/data:/data']
#
# @param env
#  A hash of additional environment variables to set in the container.
#
define s3nd::instance (
  Variant[String[1], Sensitive[String[1]]] $aws_access_key_id,
  Variant[String[1], Sensitive[String[1]]] $aws_secret_access_key,
  Optional[String[1]] $image = undef,
  Array[Stdlib::Absolutepath] $volumes = $s3nd::volumes,
  Hash $env = {},
) {
  $_image = pick($image, $s3nd::image)

  $envvars = {
    'AWS_ACCESS_KEY_ID'     => $aws_access_key_id.unwrap,
    'AWS_SECRET_ACCESS_KEY' => $aws_secret_access_key.unwrap,
  } + $s3nd::env + $env

  file { "/etc/sysconfig/s3nd-${name}":
    ensure    => file,
    show_diff => false,  # don't leak secrets in the logs
    mode      => '0600',  # only root should be able to read the secrets
    # lint:ignore:strict_indent
    # lint:ignore:variable_scope
    # lint:ignore:variables_not_enclosed
    content   => inline_epp(@(TMPL), { envvars => $envvars }),
      <%- | Hash $envvars | -%>
      <% $envvars.each | $k, $v | { -%>
      <%= $k %>=<%= $v %>
      <% } -%>
      | TMPL
    # lint:endignore
    # lint:endignore
    # lint:endignore
    notify    => Quadlets::Quadlet["s3nd-${name}.container"],
  }

  $nobody = 65534
  quadlets::quadlet { "s3nd-${name}.container":
    ensure          => present,
    active          => true,
    unit_entry      => {
      'Description' => 's3 file sending service',
      'Requires'    => 'network-online.target',
      'After'       => 'network-online.target',
    },
    container_entry => {
      'EnvironmentFile' => [
        "/etc/sysconfig/s3nd-${name}",
      ],
      'Image'           => $_image,
      'Network'         => 'host',
      'Volume'          => $volumes,
      'User'            => $nobody,
      'Group'           => $nobody,
    },
    service_entry   => {
      'Restart' => 'always',
    },
    install_entry   => {
      'WantedBy' => 'default.target',
    },
  }
}
