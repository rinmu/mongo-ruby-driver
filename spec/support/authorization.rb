# Copyright (C) 2009-2016 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The default test database for all specs.
#
# @since 2.0.0
TEST_DB = 'ruby-driver'.freeze

# The default test collection.
#
# @since 2.0.0
TEST_COLL = 'test'.freeze

# For Evergreen
if ENV['MONGODB_URI']
  MONGODB_URI = Mongo::URI.new(ENV['MONGODB_URI'])
  URI_OPTIONS = Mongo::Options::Mapper.transform_keys_to_symbols(MONGODB_URI.uri_options)
  if URI_OPTIONS[:replica_set]
    ADDRESSES = MONGODB_URI.servers
    CONNECT = { connect: :replica_set, replica_set: URI_OPTIONS[:replica_set] }
  elsif ENV['TOPOLOGY'] == 'sharded_cluster'
    ADDRESSES = [ MONGODB_URI.servers.first ] # See SERVER-16836 for why we can only use one host:port
    CONNECT = { connect: :sharded }
  else
    ADDRESSES = MONGODB_URI.servers
    CONNECT = { connect: :direct }
  end
else # For Jenkins
  ADDRESSES = ENV['MONGODB_ADDRESSES'] ? ENV['MONGODB_ADDRESSES'].split(',').freeze : [ '127.0.0.1:27017' ].freeze
  if ENV['RS_ENABLED']
    CONNECT = { connect: :replica_set, replica_set: ENV['RS_NAME'] }
  elsif ENV['SHARDED_ENABLED']
    CONNECT = { connect: :sharded }
  else
    CONNECT = { connect: :direct }
  end
end

# The write concern to use in the tests.
#
# @since 2.0.0
WRITE_CONCERN = CONNECT[:connect] == :replica_set ? { w: 2 } : { w: 1 }

# An invalid write concern.
#
# @since 2.4.2
INVALID_WRITE_CONCERN = { w: 4 }

# Whether to use SSL.
#
# @since 2.0.3
SSL = (ENV['SSL'] == 'ssl') || (ENV['SSL_ENABLED'] == 'true')

# SSL options.
#
# @since 2.1.0
SSL_OPTIONS = {
                  ssl: SSL,
                  ssl_verify: false,
                  ssl_cert:  CLIENT_CERT_PEM,
                  ssl_key:  CLIENT_KEY_PEM
                }

# Base test options.
#
# @since 2.1.0
BASE_OPTIONS = {
                  max_pool_size: 1,
                  write: WRITE_CONCERN,
                  heartbeat_frequency: 20,
                  max_read_retries: 5,
                  wait_queue_timeout: 2
               }

# Options for test suite clients.
#
# @since 2.0.3
TEST_OPTIONS = BASE_OPTIONS.merge(CONNECT).merge(SSL_OPTIONS)

# The root user name.
#
# @since 2.0.0
ROOT_USER_NAME = (defined?(MONGODB_URI) && MONGODB_URI.credentials[:user]) || 'root-user'

# The root user password.
#
# @since 2.0.0
ROOT_USER_PWD = (defined?(MONGODB_URI) && MONGODB_URI.credentials[:password]) || 'password'

# The root user auth source.
#
# @since 2.4.2
ROOT_USER_AUTH_SOURCE = (defined?(URI_OPTIONS) && URI_OPTIONS[:auth_source]) || Mongo::Database::ADMIN

# Gets the root system administrator user.
#
# @since 2.0.0
ROOT_USER = Mongo::Auth::User.new(
  user: ROOT_USER_NAME,
  password: ROOT_USER_PWD,
  roles: [
    Mongo::Auth::Roles::USER_ADMIN_ANY_DATABASE,
    Mongo::Auth::Roles::DATABASE_ADMIN_ANY_DATABASE,
    Mongo::Auth::Roles::READ_WRITE_ANY_DATABASE,
    Mongo::Auth::Roles::HOST_MANAGER,
    Mongo::Auth::Roles::CLUSTER_ADMIN
  ]
)

# Get the default test user for the suite on versions 2.6 and higher.
#
# @since 2.0.0
TEST_USER = Mongo::Auth::User.new(
  database: Mongo::Database::ADMIN,
  user: 'test-user',
  password: 'password',
  roles: [
    { role: Mongo::Auth::Roles::READ_WRITE, db: TEST_DB },
    { role: Mongo::Auth::Roles::DATABASE_ADMIN, db: TEST_DB },
    { role: Mongo::Auth::Roles::READ_WRITE, db: 'invalid_database' },
    { role: Mongo::Auth::Roles::DATABASE_ADMIN, db: 'invalid_database' }
  ]
)

# MongoDB 2.4 and lower does not allow hashes as roles, so we need to create a
# user on those versions for each database permission in order to ensure the
# legacy roles work with users. The following users are those.

# Gets the default test user for the suite on 2.4 and lower.
#
# @since 2.0.
TEST_READ_WRITE_USER = Mongo::Auth::User.new(
  database: TEST_DB,
  user: TEST_USER.name,
  password: TEST_USER.password,
  roles: [ Mongo::Auth::Roles::READ_WRITE, Mongo::Auth::Roles::DATABASE_ADMIN ]
)

# Provides an authorized mongo client on the default test database for the
# default test user.
#
# @since 2.0.0
AUTHORIZED_CLIENT = Mongo::Client.new(
  ADDRESSES,
  TEST_OPTIONS.merge(
    database: TEST_DB,
    user: TEST_USER.name,
    password: TEST_USER.password)
)

# Provides an unauthorized mongo client on the default test database.
#
# @since 2.0.0
UNAUTHORIZED_CLIENT = Mongo::Client.new(
  ADDRESSES,
  TEST_OPTIONS.merge(database: TEST_DB, monitoring: false)
)

# Provides an unauthorized mongo client on the admin database, for use in
# setting up the first admin root user.
#
# @since 2.0.0
ADMIN_UNAUTHORIZED_CLIENT = Mongo::Client.new(
  ADDRESSES,
  TEST_OPTIONS.merge(database: Mongo::Database::ADMIN, monitoring: false)
)

# Get an authorized client on the test database logged in as the admin
# root user.
#
# @since 2.0.0
ADMIN_AUTHORIZED_TEST_CLIENT = ADMIN_UNAUTHORIZED_CLIENT.with(
  user: ROOT_USER.name,
  password: ROOT_USER.password,
  database: TEST_DB,
  auth_source: ROOT_USER_AUTH_SOURCE,
  monitoring: false
)

module Authorization

  # On inclusion provides helpers for use with testing with and without
  # authorization.
  #
  #
  # @since 2.0.0
  def self.included(context)

    # Gets the root system administrator user.
    #
    # @since 2.0.0
    context.let(:root_user) { ROOT_USER }

    # Get the default test user for the suite.
    #
    # @since 2.0.0
    context.let(:test_user) { TEST_USER }

    # Provides an authorized mongo client on the default test database for the
    # default test user.
    #
    # @since 2.0.0
    context.let(:authorized_client) { AUTHORIZED_CLIENT }

    # Provides an unauthorized mongo client on the default test database.
    #
    # @since 2.0.0
    context.let!(:unauthorized_client) { UNAUTHORIZED_CLIENT }

    # Provides an unauthorized mongo client on the admin database, for use in
    # setting up the first admin root user.
    #
    # @since 2.0.0
    context.let!(:admin_unauthorized_client) { ADMIN_UNAUTHORIZED_CLIENT }

    # Get an authorized client on the test database logged in as the admin
    # root user.
    #
    # @since 2.0.0
    context.let!(:root_authorized_client) { ADMIN_AUTHORIZED_TEST_CLIENT }

    # Gets the default test collection from the authorized client.
    #
    # @since 2.0.0
    context.let(:authorized_collection) do
      authorized_client[TEST_COLL]
    end

    # Gets the default test collection from the unauthorized client.
    #
    # @since 2.0.0
    context.let(:unauthorized_collection) do
      unauthorized_client[TEST_COLL]
    end

    # Gets a primary server for the default authorized client.
    #
    # @since 2.0.0
    context.let(:authorized_primary) do
      authorized_client.cluster.next_primary
    end

    # Get a primary server for the client authorized as the root system
    # administrator.
    #
    # @since 2.0.0
    context.let(:root_authorized_primary) do
      root_authorized_client.cluster.next_primary
    end

    # Get a primary server from the unauthorized client.
    #
    # @since 2.0.0
    context.let(:unauthorized_primary) do
      authorized_client.cluster.next_primary
    end

    # Get a default address (of the primary).
    #
    # @since 2.2.6
    context.let(:default_address) do
      authorized_client.cluster.next_primary.address
    end

    # Get a default app metadata.
    #
    # @since 2.4.0
    context.let(:app_metadata) do
      authorized_client.cluster.app_metadata
    end
  end
end
