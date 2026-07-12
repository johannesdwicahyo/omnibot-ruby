require "rails/generators"
require "generators/omnibot/install/install_generator"
require "generators/omnibot/agent/agent_generator"

RSpec.describe "generators" do
  let(:tmp) { File.expand_path("../../tmp/generators", __dir__) }

  before { FileUtils.rm_rf(tmp); FileUtils.mkdir_p(tmp) }

  # Thor prints "create <path>" status lines to $stdout on every invocation;
  # silence that so the spec run stays pristine.
  def quietly
    original = $stdout
    $stdout = File.open(File::NULL, "w")
    yield
  ensure
    $stdout = original
  end

  it "omnibot:install creates the initializer" do
    quietly { Omnibot::Generators::InstallGenerator.start([], destination_root: tmp) }
    content = File.read(File.join(tmp, "config/initializers/omnibot.rb"))
    expect(content).to include("Omnibot.configure")
    expect(content).to include("default_model")
  end

  it "omnibot:agent creates agent + spec" do
    quietly { Omnibot::Generators::AgentGenerator.start(["Support"], destination_root: tmp) }
    agent = File.read(File.join(tmp, "app/agents/support_agent.rb"))
    expect(agent).to include("class SupportAgent < Omnibot::Agent")
    spec = File.read(File.join(tmp, "spec/agents/support_agent_spec.rb"))
    expect(spec).to include("Omnibot::Testing.fake!")
    expect(spec).to include("stub_agent(SupportAgent)")
  end
end
