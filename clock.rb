require "clockwork"
require "rest-client"
require_relative './lib/admin/admin_server'

PagerBot.reload_configuration!

module Clockwork
  class SlackHelper
    def self.oncall_slack_channel_id
      unless @oncall_slack_channel_id
        channel_name = PagerBot.configatron.plugins.reveille.channel

        r = RestClient.post("https://slack.com/api/channels.list",
                            {:token => PagerBot.configatron.bot.slack.api_token})
        slack_channels = JSON.parse(r.body)["channels"]
        slack_channel = slack_channels.find { |c| c["name"] == channel_name }
        if slack_channel.blank?
          raise "could not find slack channel ##{channel_name}"
        end
        @oncall_slack_channel_id = slack_channel["id"]
      end
      @oncall_slack_channel_id
    end

    def self.msg_oncall_channel(msg)
      RestClient.post("https://slack.com/api/chat.postMessage",
                      {
                        :username => PagerBot.configatron.bot.name,
                        :icon_emjoi => PagerBot.configatron.bot.slack.emoji,
                        :text => msg,
                        :channel => SlackHelper.oncall_slack_channel_id,
                        :token => PagerBot.configatron.bot.slack.api_token
                      })
    end
  end

  every(1.day,
        "reveille",
        at: "08:01",
        tz: "America/Los_Angeles") do
    SlackHelper.msg_oncall_channel("pagerbot reveille")
  end
end
