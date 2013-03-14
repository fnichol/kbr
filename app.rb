require 'sinatra'
require 'json'
require 'logger'
require 'faraday'
require 'faraday_middleware'
require 'faraday-http-cache'
require 'redis-activesupport'

module KBR

  class GitHubClient

    def initialize(opts = {})
      @connection = Faraday.new(url: 'https://api.github.com') do |builder|
        builder.response :json, content_type: /\bjson$/
        builder.use :http_cache, *opts[:cache_opts]
        builder.adapter Faraday.default_adapter
      end
    end

    def tags(user, repo)
      @connection.get("/repos/#{user}/#{repo}/git/refs/tags")
    end
  end

  class App < Sinatra::Base

    configure do
      enable :logging
      set :redis_url, (ENV['REDIS_URL'] || "redis://127.0.0.1:6379")
    end

    get '/tags/:user/:repo' do
      content_type :json

      response = github_client.tags(params[:user], params[:repo])

      if response.success?
        response.body.map { |t| t["ref"].split("/").last }.sort.to_json
      else
        response.status
      end
    end

    private

    def github_client
      GitHubClient.new(cache_opts: [
        :redis_store, settings.redis_url, logger: Logger.new(STDOUT)
      ])
    end
  end
end
