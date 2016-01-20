module PagerBot::Plugins
  class Reveille
    include PagerBot::PluginBase
    responds_to :queries, :manual
    description "Notify the primary person and invite them to the on-call channel."
    required_fields 'channel'

    def initialize(config)
      @channel = config.fetch(:channel)
    end

    def self.manual
      {
        description: "Notify the primary for today and invite to ##{@channel}.",
        syntax: ["reveille"],
        examples: ["reveille"]
      }
    end

    def parse(query)
      return {} if query[:command] == "reveille"
    end

    +PagerBot::Utilities::DispatchMethod
    def dispatch(query, event_data)
      schedule = pagerduty.find_schedule("primary")
      time = pagerduty.parse_time("now", nil)

      schedule_info = pagerduty.get(
        "/schedules/#{schedule.id}",
        :params => {
          :since => time.iso8601,
          :until => (time + 1).iso8601
        })

      entries = schedule_info[:schedule][:final_schedule][:rendered_schedule_entries]

      if entries.empty?
        return "There's nobody on call!"
      end

      user_email = entries.first[:user][:email]
      slack_api_token = PagerBot.configatron.bot.slack.api_token

      # Map the user email to Slack user id
      r = RestClient.post("https://slack.com/api/users.list",
                          {:token => slack_api_token})
      slack_users = JSON.parse(r.body)["members"]
      slack_user = slack_users.find { |u| u["profile"]["email"] == user_email }
      if slack_user.blank?
        return "#{user_email} is on-call primary but not on Slack."
      end

      # Map the channel name to Slack channel id
      r = RestClient.post("https://slack.com/api/channels.list",
                          {:token => slack_api_token})
      slack_channels = JSON.parse(r.body)["channels"]
      slack_channel = slack_channels.find { |c| c["name"] == @channel }
      if slack_channel.blank?
        return "Slack channel ##{channel} could not be found."
      end

      slack_user_id = slack_user["id"]
      slack_username = slack_user["name"]
      slack_channel_id = slack_channel["id"]

      # Invite on-call primary user to the channel
      r = RestClient.post("https://slack.com/api/channels.invite",
                          {
                            :channel => slack_channel_id,
                            :user => slack_user_id,
                            :token => slack_api_token
                          })

      render "reveille", {:slack_user_id => slack_user_id,
                          :slack_username => slack_username}
    end
  end
end
