class { 's3nd':
  image     => 'ghcr.io/lsst-dm/s3nd:sha-e9bfaa0',
  volumes   => ['/home:/home', '/var:/foo'],
  env       => {
    'QUUX'      => 'corge',
  },
  instances => {
    'foo' => {
      'port'                  => 15556,
      'aws_access_key_id'     => 'access_key_id',
      'aws_secret_access_key' => 'secret_access_key',
      'image'                 => 'ghcr.io/lsst-dm/s3nd:main',
      'env'                   => {
        'S3ND_ENDPOINT_URL' => 'https://s3.foo.example.com',
        'FOO'               => 'bar',
      },
    },
    'bar' => {
      'port'                  => 15557,
      'aws_access_key_id'     => 'access_key_id',
      'aws_secret_access_key' => 'secret_access_key',
      'volumes'               => ['/home:/home', '/opt:/opt'],
      'env'                   => {
        'S3ND_ENDPOINT_URL' => 'https://s3.bar.example.com',
        'BAZ'               => 'qux',
      },
    },
  },
}
