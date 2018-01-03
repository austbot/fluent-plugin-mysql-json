require 'helper'
require 'fluent/plugin/out_mysql_json.rb'
require 'mysql2-cs-bind'

class MysqlJsonOutputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup
  end

  CONFIG = {
      host: 'mysql',
      database: 'logs',
      username: 'test',
      password: 'test',
      port: 3306
  }

  private

  def conf
    CONFIG.merge({table_name: 'logs'}).reduce("") {|sum, (key, val)| sum + "#{key} #{val}\n"}
  end

  def create_driver(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::MysqlJsonOutputTest).configure(conf)
  end

  def test_configure_error
    assert_raise(Fluent::ConfigError) do
      create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
      ]
    end

  end

  def test_configure
    # not define format(default csv)
    assert_nothing_raised(Fluent::ConfigError) do
      create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        table_name users
      ]
    end
  end

  sub_test_case 'Write' do
    test 'to test #write' do
      mysqlClient = Mysql2::Client.new(CONFIG)
      d = create_driver(conf)
      t = event_time('2016-06-10 19:46:32 +0900')
      key = 'thisisrandom'
      d.run do
        d.feed('tag', t, {'id'=> key, 'message' => 'this is test message', 'amount' => 53})
      end
      r = mysqlClient.xquery('SELECT log->>"$.id" as id FROM logs WHERE log->"$.id" = ?', key)
      assert {
        r.count > 0 and r.to_a[0]['id'] == key
      }
    end
  end
end
