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
      @connection = Faraday.new(url: opts[:api_url]) do |builder|
        builder.response :json, content_type: /\bjson$/
        builder.use :http_cache, *opts[:cache_opts]
        builder.adapter Faraday.default_adapter
      end
      @client_id = opts[:client_id]
      @client_secret = opts[:client_secret]
    end

    def tags(user, repo)
      @connection.get("/repos/#{user}/#{repo}/git/refs/tags",
        client_id: @client_id, client_secret: @client_secret)
    end
  end

  class App < Sinatra::Base

    configure do
      enable :logging
      set :redis_url, (ENV['REDIS_URL'] || "redis://127.0.0.1:6379")
      set :gh_api_url, (ENV['GITHUB_API_URL'] || "https://api.github.com")
      set :gh_client_id, ENV['GITHUB_CLIENT_ID']
      set :gh_client_secret, ENV['GITHUB_CLIENT_SECRET']
    end

    get '/tags/:user/:repo' do
      content_type :json
      response = github_client.tags(params[:user], params[:repo])
      stats = [
        "repo=#{params[:user]}/#{params[:repo]}",
        "status=#{response.status}",
        "rate_limit=#{rate_limit(response.headers)}",
      ].join(" ")

      if response.success?
        tags = response.body.map { |t| t["ref"].split("/").last }.sort
        stats << " tags=#{tags.join(",")}"
        logger.info stats
        tags.to_json
      else
        logger.warn stats
        response.status
      end

    end

    private

    def github_client
      GitHubClient.new(
        api_url: settings.gh_api_url,
        client_id: settings.gh_client_id,
        client_secret: settings.gh_client_secret,
        cache_opts: [
          :redis_store, settings.redis_url, logger: Logger.new(STDOUT)
        ]
      )
    end

    def rate_limit(headers)
      "#{headers['X-RateLimit-Remaining']}/#{headers['X-RateLimit-Limit']}"
    end
  end
end
