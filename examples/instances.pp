class { 's3daemon':
  instances => {
    'foo' => {
      's3_endpoint_url'       => 'https://s3.foo.example.com',
      'aws_access_key_id'     => 'access_key_id',
      'aws_secret_access_key' => 'secret_access_key',
      'port'                  => 15556,
      'image'                 => 'ghcr.io/lsst-dm/s3daemon:main',
    },
    'bar' => {
      's3_endpoint_url'       => 'https://s3.bar.example.com',
      'aws_access_key_id'     => 'access_key_id',
      'aws_secret_access_key' => 'secret_access_key',
      'port'                  => 15557,
      'image'                 => 'ghcr.io/lsst-dm/s3daemon:sha-b5e72fa',
      'volumes'               => ['/home:/home', '/opt:/opt'],
      'env'                   => {
        'FOO' => 'bar',
        'BAZ' => 'quix',
      },
    },
  },
}
