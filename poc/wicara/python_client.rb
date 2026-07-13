require "faraday"
require "securerandom"
require "json"

module WicaraPoc
  class PythonClient
    def initialize(url:, token:)
      @url = url
      @token = token
      @client = Faraday.new(url: @url) do |conn|
        conn.adapter Faraday.default_adapter
      end
    end

    # GET /v1/health with auth header
    # Returns true iff status 200, false otherwise
    def health
      response = @client.get("/v1/health", {}, headers)
      response.status == 200
    rescue
      false
    end

    # POST /v1/chat per wicara contract
    # history entries are enriched with `id: SecureRandom.uuid`
    # Returns symbolized-key response or raises on non-200
    def chat(workspace_id:, bot_id:, conversation_id:, user_message:, history:)
      enriched_history = history.map do |entry|
        entry.merge("id" => SecureRandom.uuid)
      end

      payload = {
        workspace_id: workspace_id,
        bot_id: bot_id,
        conversation_id: conversation_id,
        user_message: user_message,
        history: enriched_history,
        metadata: {
          channel: "widget",
          channel_user_id: "poc"
        }
      }

      response = @client.post("/v1/chat", payload.to_json, headers.merge("Content-Type" => "application/json"))

      unless response.status == 200
        raise "HTTP #{response.status}: #{response.body}"
      end

      JSON.parse(response.body, symbolize_names: true)
    end

    private

    def headers
      {
        "X-Wicara-Internal-Token" => @token
      }
    end
  end
end
