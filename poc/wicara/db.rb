require "pg"
require "json"

module WicaraPoc
  # SELECT-only access to the wicara Rails/AI schema. Read-only: never writes.
  class DB
    def initialize(url)
      @conn = PG.connect(url)
    end

    # PoC convenience finder (not a port of bot.py, which requires an explicit
    # bot_id + workspace_id and raises on miss). With slug: nil, picks the
    # first bot whose config->kb_ids is a non-empty array, so the offline
    # smoke has something to search against. The resources-loading branch
    # below DOES mirror ai/app/models/bot.py's _load_active_resources.
    def load_bot(slug: nil)
      row =
        if slug
          @conn.exec_params(
            "SELECT id, workspace_id, config FROM public.bots WHERE slug = $1 LIMIT 1", [slug]
          ).first
        else
          @conn.exec(<<~SQL).first
            SELECT id, workspace_id, config
            FROM public.bots
            WHERE jsonb_typeof(config->'kb_ids') = 'array'
              AND jsonb_array_length(config->'kb_ids') > 0
            ORDER BY created_at ASC
            LIMIT 1
          SQL
        end
      return nil unless row

      config = JSON.parse(row["config"])
      tools = Array(config["tools"])
      config["resources"] = tools.include?("share_lead_magnet") ? load_resources(row["id"]) : []
      { id: row["id"], workspace_id: row["workspace_id"], config: config }
    end

    # Verbatim KB search SQL (see docs/superpowers/plans/2026-07-14-wicara-poc.md
    # "Wicara contract facts"). qvec_literal is a pgvector literal "[v1,v2,...]";
    # kb_ids is a Postgres uuid[] literal "{uuid,uuid}".
    def search_kb(workspace_id:, kb_ids:, qvec_literal:, k: 5)
      rows = @conn.exec_params(<<~SQL, [qvec_literal, workspace_id, uuid_array_literal(kb_ids), k])
        SELECT c.kb_document_id, c.chunk_index, c.text,
               1.0 - (c.embedding <=> CAST($1 AS vector)) AS score
        FROM ai.kb_chunks c
        JOIN public.kb_documents d ON d.id = c.kb_document_id
        JOIN public.kbs k ON k.id = d.kb_id AND k.workspace_id = $2
        WHERE d.kb_id = ANY($3)
        ORDER BY c.embedding <=> CAST($1 AS vector)
        LIMIT $4
      SQL

      rows.map do |r|
        {
          kb_document_id: r["kb_document_id"],
          chunk_index: r["chunk_index"].to_i,
          text: r["text"],
          score: r["score"].to_f
        }
      end
    end

    private

    # Mirrors ai/app/models/bot.py#_load_active_resources verbatim (SQL + shape).
    def load_resources(bot_id)
      @conn.exec_params(<<~SQL, [bot_id]).map { |r| { id: r["id"], label: r["label"], description: r["description"].to_s } }
        SELECT id::text, label, description
        FROM public.resources
        WHERE bot_id = $1 AND archived_at IS NULL
        ORDER BY created_at ASC
      SQL
    end

    def uuid_array_literal(ids) = "{#{Array(ids).join(',')}}"
  end
end
