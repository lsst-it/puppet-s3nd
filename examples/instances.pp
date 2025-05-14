class { 's3daemon':
  image     => 'ghcr.io/lsst-dm/s3daemon:sha-b5e72fa',
  env       => {
    'S3DAEMON_PORT' => 15556,
    'QUUX'          => 'corge',
  },
  instances => {
    'foo' => {
      'aws_access_key_id'     => 'access_key_id',
      'aws_secret_access_key' => 'secret_access_key',
      'image'                 => 'ghcr.io/lsst-dm/s3daemon:main',
      'env'                   => {
        'S3_ENDPOINT_URL' => 'https://s3.foo.example.com',
        'FOO'             => 'bar',
      },
    },
    'bar' => {
      'aws_access_key_id'     => 'access_key_id',
      'aws_secret_access_key' => 'secret_access_key',
      'volumes'               => ['/home:/home', '/opt:/opt'],
      'env'                   => {
        'S3_ENDPOINT_URL' => 'https://s3.bar.example.com',
        'S3DAEMON_PORT'   => 15557,
        'BAZ'             => 'qux',
      },
    },
  },
}
