require 'sinatra/base'
require 'json'
require 'mongo'
require 'set'
require 'active_support/core_ext/hash/indifferent_access'
require_relative '../pagerbot'
require_relative '../pagerbot/datastore'
require_relative '../pagerbot/pagerduty'
require_relative '../pagerbot/plugin/plugin_manager'
require_relative '../pagerbot/utilities'
include Mongo

module PagerBot
  class AdminPage < Sinatra::Base
    set :public_folder, 'public'

    helpers do
      def protected!
        unless authorized?
          response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
          throw(:halt, [401, "Not authorized\n"])
        end
      end

      def authorized?
        return true if ENV['PROTECT_ADMIN'].nil?
        @auth ||= Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials[1] == ENV['PROTECT_ADMIN']
      end

      def json_args(request)
        text = request.env["rack.input"].read
        hash = JSON.parse(text).with_indifferent_access
        hash
      end

      def db
        store.db
      end

      def store
        @store ||= PagerBot::DataStore.new
      end

      def can_connect_to_pd(pagerduty=nil)
        pagerduty = store.get_pagerduty
        begin
          pagerduty.get('/users')
          true
        rescue Exception => e
          puts("#{e.message}")
          false
        end
      end
    end

    get '/' do
      protected!
      File.new('public/index.html').readlines
    end

    get '/pagerduty' do
      protected!
      content_type :json
      ({
        pagerduty: store.get_or_create('pagerduty'),
        can_connect: can_connect_to_pd
      }).to_json
    end

    post '/pagerduty' do
      protected!
      content_type :json
      args = json_args request
      args.delete('_id')

      db['pagerduty'].update({}, args, :upsert => true)

      response = {
        can_connect: can_connect_to_pd,
        saved: store.get_or_create('pagerduty')
      }
      response.to_json
    end

    bot_defaults = {
      name: 'pagerbot',
      channels: ['general'],
      adapter: 'slack',
      irc: {
        server: 'irc.freenode.org',
        port: 6697,
        use_ssl: false,
      },
      slack: {
        emoji: ':frog:'
      },
      hipchat: {}
    }

    get '/bot' do
      protected!
      content_type :json

      store.get_or_create('bot', bot_defaults).to_json
    end

    post '/bot' do
      protected!
      content_type :json

      args = json_args request
      args.delete('_id')
      db['bot'].update({}, args, :upsert => true)
      {
        saved: store.get_or_create('bot', bot_defaults)
      }.to_json
    end

    get '/plugins' do
      protected!
      content_type :json

      available = PagerBot::PluginManager
        .available_plugins.sort.map do |name|
          ret = PagerBot::PluginManager.info name
          plugin = db['plugins'].find_one({name:name})
          if plugin
            ret[:enabled] = plugin.fetch('enabled')
            ret[:settings] = plugin.fetch('settings')
          else
            ret[:enabled] = ret[:required_fields].empty? && ret[:required_plugins].empty?
            ret[:settings] = {}
            db['plugins'].save(ret)
          end
          ret
        end

      {
        plugins: available
      }.to_json
    end

    post '/plugins' do
      protected!
      content_type :json
      # puts request.env["rack.input"].read
      plugins = json_args(request).fetch(:plugins)
      store.update_listed('plugins', plugins, :name)

      {
        saved: {
          plugins: store.db_get_list_of('plugins')
        }
      }.to_json
    end

    # Alias api methods
    post '/normalize_strings' do
      protected!
      content_type :json

      strings = json_args(request).fetch(:strings)
      {
        strings: strings.map {|s| PagerBot::Utilities.normalize(s)}
      }.to_json
    end

    get '/users' do
      protected!
      content_type :json

      users, added, removed = store.update_collection! 'users'
      {
        users: users,
        pagerduty: store.get_or_create('pagerduty'),
        added: added,
        removed: removed
      }.to_json
    end

    post '/users' do
      protected!
      content_type :json
      added_users = json_args(request).fetch(:users)

      store.update_listed('users', added_users)

      users_collection = PagerBot::Models::Collection.new(
        store.db_get_list_of('users'),
        PagerBot::Models::Users)
      {
        saved: {users: users_collection.serializable_list}
      }.to_json
    end

    get '/schedules' do
      protected!
      content_type :json

      schedules, added, removed = store.update_collection! 'schedules'
      {
        schedules: schedules,
        pagerduty: store.get_or_create('pagerduty'),
        added: added,
        removed: removed
      }.to_json
    end

    post '/schedules' do
      protected!
      content_type :json
      added_schedules = json_args(request).fetch(:schedules)

      store.update_listed('schedules', added_schedules)

      schedule_collection = PagerBot::Models::Collection.new(
        store.db_get_list_of('schedules'),
        PagerBot::Models::Schedule)
      {
        saved: {schedules: schedule_collection.serializable_list}
      }.to_json
    end
  end
end

if __FILE__ == $0
  PagerBot::AdminPage.run!
end