#
# Copyright 2017- austbot
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/output'
require 'securerandom'

module Fluent::Plugin
  class MysqlJsonOutputTest < Output
    Fluent::Plugin.register_output('mysql_json', self)

    helpers :compat_parameters, :inject

    config_param :host, :string, default: '127.0.0.1', desc: 'Database host.'
    config_param :port, :integer, default: 3306, desc: 'Database port.'
    config_param :database, :string, desc: 'Database name.'
    config_param :username, :string, desc: 'Database user.'
    config_param :password, :string, default: '', secret: true, desc: 'Database password.'
    config_param :sslkey, :string, default: nil, desc: 'SSL key.'
    config_param :sslcert, :string, default: nil, desc: 'SSL cert.'
    config_param :sslca, :string, default: nil, desc: 'SSL CA.'
    config_param :sslcapath, :string, default: nil, desc: 'SSL CA path.'
    config_param :sslcipher, :string, default: nil, desc: 'SSL cipher.'
    config_param :sslverify, :bool, default: nil, desc: 'SSL Verify Server Certificate.'
    config_param :table_name, :string, desc: 'Bulk insert table.'

    attr_accessor :handler

    def initialize
      super
      require 'mysql2-cs-bind'
    end

    def configure(conf)
      super
      compat_parameters_convert(conf, :buffer, :inject)
      log.info(conf)
      create_table
    end

    def create_table(database: @database, table: @table_name)
      client(database).xquery("CREATE TABLE IF NOT EXISTS #{table}(seq int NOT NULL AUTO_INCREMENT, id varchar(25), event_time TIMESTAMP, log JSON, PRIMARY KEY (seq))", [])
    end

    def format(tag, time, record)
      record = inject_values_to_record(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def formatted_to_msgpack_binary
      true
    end

    def multi_workers_ready?
      true
    end

    def client(database)
      Mysql2::Client.new(
          host: @host,
          port: @port,
          username: @username,
          password: @password,
          database: database,
          sslkey: @sslkey,
          sslcert: @sslcert,
          sslca: @sslca,
          sslcapath: @sslcapath,
          sslcipher: @sslcipher,
          sslverify: @sslverify,
          flags: Mysql2::Client::MULTI_STATEMENTS
      )
    end

    def expand_placeholders(metadata)
      database = extract_placeholders(@database, metadata).gsub('.', '_')
      table = extract_placeholders(@table_name, metadata).gsub('.', '_')
      return database, table
    end

    def write(chunk)
      database, table = expand_placeholders(chunk.metadata)
      @handler = client(database)
      values = []
      values_template = '(?, ?, ?)'
      chunk.msgpack_each do |tag, time, data|
        data = format_proc.call(tag, time, data)
        values << Mysql2::Client.pseudo_bind(values_template, data)
      end
      sql = "INSERT INTO #{table} (id, event_time, log) VALUES #{values.join(', ')}"
      log.info "bulk insert values size (table: #{table}) => #{values.size}"
      @handler.xquery(sql)
      @handler.close
    end

    private

    def format_proc
      proc do |tag, time, record|
        rand = SecureRandom.base64(13) + time.to_s
        t = Time.at(time).strftime('%Y-%m-%d %H:%M:%S')
        d = record.to_json
        id = rand[0..24]
        [id, t, d]
      end
    end
  end
end

