require "omnibot"
require_relative "system_prompt"
require_relative "embedder"

module WicaraPoc
  # Set by the request_handover tool and by the anger fast path. Agent has no
  # native handover primitive, so the harness reads this module-level slot
  # after a run and resets it between turns/specs.
  #
  # last_kb_results: set by the search_knowledge_base tool to the raw rows
  # returned by DB#search_kb ({kb_document_id:, chunk_index:, text:, score:}).
  # The omnibot.tool.call notification payload doesn't carry the tool's return
  # value, so the harness reads citations from here instead of re-parsing the
  # marker text it hands back to the LLM. Reset between turns like
  # last_handover.
  class << self
    attr_accessor :last_handover, :last_kb_results
  end

  GREETING_TOKENS = %w[hi hello hey yo hiya halo hai pagi siang sore malam selamat test testing ping].freeze

  PROFANITY_REGEX =
    /\b(fuck|shit|bitch|asshole|bastard|dickhead|wanker|anjing|bangsat|kontol|memek|tai|tolol|goblok|babi|bajingan|brengsek)\b/i

  def self.greeting?(message)
    words = message.to_s.gsub(/\W+/, " ").downcase.split
    return false if words.empty? || words.length > 2
    words.all? { |w| GREETING_TOKENS.include?(w) }
  end

  # Builds a fresh Omnibot::Agent subclass wired to this bot's config.
  # NOTE: this also overrides the *global* Omnibot.chat_factory (there is no
  # per-class factory hook) — fine for this single-agent-at-a-time PoC, not
  # safe for concurrent bots in one process.
  def self.build_agent(bot:, db:)
    config = bot[:config]
    embedder = FakeEmbedder.new
    anger_counts = Hash.new(0)
    greeting_menu = config["greeting_menu"].to_s
    anger_threshold = config["handover_on_anger_threshold"].to_i
    tool_names = Array(config["tools"])

    klass = Class.new(Omnibot::Agent) do
      model config.dig("model", "model") || "gpt-4o-mini"
      instructions SystemPrompt.build(config)
      max_turns 4

      fast_path do |message, _context|
        reply(greeting_menu) if !greeting_menu.empty? && WicaraPoc.greeting?(message)
      end

      fast_path do |message, context|
        next if anger_threshold <= 0
        next unless message.to_s.match?(WicaraPoc::PROFANITY_REGEX)

        conversation_id = context[:conversation_id] || context["conversation_id"]
        count = anger_counts[conversation_id] += 1
        if count >= anger_threshold
          WicaraPoc.last_handover = { requested: true, reason: "anger threshold reached (#{count} profane turns)" }
          reply("")
        end
      end

      if tool_names.include?("search_knowledge_base")
        tool :search_knowledge_base, "Search the bot's knowledge base for passages relevant to a query." do |query:, k: 5|
          vec = embedder.embed_query(query)
          rows = db.search_kb(workspace_id: bot[:workspace_id], kb_ids: config["kb_ids"],
                               qvec_literal: embedder.to_pgvector(vec), k: k)
          WicaraPoc.last_kb_results = rows
          if rows.empty?
            "No matching passages."
          else
            rows.map { |r| "[doc=#{r[:kb_document_id]} chunk=#{r[:chunk_index]} score=#{'%.3f' % r[:score]}]\n#{r[:text]}" }
                .join("\n---\n")
          end
        end
      end

      if tool_names.include?("request_handover")
        tool :request_handover, "Request handover of this conversation to a human agent." do |reason:|
          WicaraPoc.last_handover = { requested: true, reason: reason }
          "Handover requested: #{reason}"
        end
      end

      if tool_names.include?("capture_lead")
        tool :capture_lead, "Capture a visitor's contact details as a lead." do |name: "", email: "", phone: "", notes: ""|
          "Saved contact (contact_id=poc-stub)."
        end
      end
    end

    Omnibot.chat_factory = lambda do |model:, **|
      RubyLLM.chat(model: model).with_temperature(config.dig("model", "temperature")&.to_f || 0.2)
    end

    klass
  end
end
