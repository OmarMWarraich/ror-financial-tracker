require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

class ComposeEnvTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("financial-tracker-compose-")
    FileUtils.mkdir_p(File.join(@directory, "bin"))
    FileUtils.cp(File.expand_path("../../bin/compose-env", __dir__), File.join(@directory, "bin/compose-env"))
    FileUtils.cp(File.expand_path("../../.env.example", __dir__), File.join(@directory, ".env.example"))
    @path = File.join(@directory, ".env.docker")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_generates_independent_private_local_secrets_without_printing_them
    output, error, status = generate
    assert status.success?, error
    assert_equal 0o600, File.stat(@path).mode & 0o777
    values = File.readlines(@path, chomp: true).grep(/\A(?:POSTGRES_PASSWORD|SECRET_KEY_BASE|ACTIVE_RECORD_ENCRYPTION_\w+)=/).
      map { |line| line.split("=", 2).last }
    assert_equal 5, values.length
    assert_equal 5, values.uniq.length
    values.each do |value|
      assert_match(/\A[0-9a-f]{64}\z/, value)
      refute_includes output + error, value
    end
  end

  def test_refuses_to_replace_existing_secrets
    File.write(@path, "existing-volume-secrets\n")
    output, error, status = generate
    refute status.success?
    assert_empty output
    assert_includes error, "already exists; it was not changed"
    assert_equal "existing-volume-secrets\n", File.read(@path)
  end

  private

  def generate
    Open3.capture3(RbConfig.ruby, File.join(@directory, "bin/compose-env"))
  end
end
