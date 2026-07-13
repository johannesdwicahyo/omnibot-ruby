require "digest"

module WicaraPoc
  # Bit-exact port of wicara ai/app/ingest/embedder.py FakeEmbedder.
  class FakeEmbedder
    def initialize(dim: 1536) = @dim = dim

    def embed_query(text)
      seed = Digest::SHA256.digest(text.encode("utf-8"))
      out = []
      while out.length < @dim
        seed = Digest::SHA256.digest(seed)
        seed.each_byte { |b| out << (b - 128) / 128.0 }
      end
      out = out.first(@dim)
      norm = Math.sqrt(out.sum { |v| v * v })
      norm = 1.0 if norm.zero?
      out.map { |v| v / norm }
    end

    def to_pgvector(vec) = "[#{vec.join(',')}]"
  end
end
