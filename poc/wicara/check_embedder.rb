require_relative "embedder"

texts = ["hello", "selamat pagi", "Where is my order?", ""]
ruby = WicaraPoc::FakeEmbedder.new
python = <<~PY
  import hashlib, math, json, sys
  def embed(text, dim=1536):
      digest = hashlib.sha256(text.encode("utf-8")).digest()
      out = []; seed = digest
      while len(out) < dim:
          seed = hashlib.sha256(seed).digest()
          out.extend((b - 128) / 128.0 for b in seed)
      out = out[:dim]
      norm = math.sqrt(sum(v*v for v in out)) or 1.0
      return [v / norm for v in out]
  print(json.dumps([embed(t) for t in json.loads(sys.argv[1])]))
PY
require "json"
require "open3"
expected, status = Open3.capture2("python3", "-c", python, JSON.generate(texts))
abort "python3 reference failed" unless status.success?
expected = JSON.parse(expected)

texts.each_with_index do |t, i|
  got = ruby.embed_query(t)
  ref = expected[i]
  raise "dim mismatch" unless got.length == ref.length
  max_delta = got.zip(ref).map { |a, b| (a - b).abs }.max
  raise "NOT bit-exact for #{t.inspect}: max delta #{max_delta}" if max_delta > 1e-12
  puts "✓ #{t.inspect} max_delta=#{max_delta}"
end
puts "embedder bit-exact ✅"
