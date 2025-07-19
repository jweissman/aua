require "spec_helper"

RSpec.describe "Extended Builtin Functions" do
  describe "list_files builtin" do
    before do
      # Create a test directory with files
      FileUtils.mkdir_p("/tmp/test_dir")
      File.write("/tmp/test_dir/file1.txt", "content1")
      File.write("/tmp/test_dir/file2.yml", "content2")
      File.write("/tmp/test_dir/file3.aura", "content3")
    end

    after do
      FileUtils.rm_rf("/tmp/test_dir")
    end

    it "lists files in a directory" do
      result = Aua.run('list_files("/tmp/test_dir")')
      expect(result).to be_a(Aua::List)
      filenames = result.values.map(&:value)
      expect(filenames).to include("file1.txt", "file2.yml", "file3.aura")
    end

    it "returns empty list for non-existent directory" do
      result = Aua.run('list_files("/nonexistent")')
      expect(result).to be_a(Aua::List)
      expect(result.values).to be_empty
    end
  end

  describe "write_file builtin" do
    let(:file_path) { "/tmp/test_write_file.txt" }
    after do
      File.delete(file_path) if File.exist?(file_path)
    end

    it "writes content to a file" do
      content = "Hello, Aura!"
      result = Aua.run("write_file('#{file_path}', '#{content}')")
      expect(result).to be_a(Aua::Nihil)

      expect(File.exist?(file_path)).to be true
      expect(File.read(file_path)).to eq(content)
    end
  end

  describe "parse_yaml builtin" do
    let(:yaml_content) do
      <<~YAML
        key1: value1
        key2:
          - item1
          - item2
      YAML
    end

    it "parses YAML content into Aura objects" do
      result = Aua.run("parse_yaml('#{yaml_content}')")
      expect(result).to be_a(Aua::Dict)
      expect(result.get_field("key1").value).to eq("value1")
      expect(result.get_field("key2")).to be_a(Aua::List)
      expect(result.get_field("key2").values.map(&:value)).to contain_exactly("item1", "item2")
    end
  end

  describe "dump_yaml builtin" do
    it "dumps Aura objects to YAML format" do
      # dict = Aua::Dict.new
      # dict.set_field("key1", Aua::Str.new("value1"))
      # dict.set_field("key2", Aua::List.new([Aua::Str.new("item1"), Aua::Str.new("item2")]))

      result = Aua.run("dump_yaml({ key1: 'value1', key2: ['item1', 'item2'] })")
      expect(result).to be_a(Aua::Str)

      expected_yaml = <<~YAML.chomp
        ---
        key1: value1
        key2:
        - item1
        - item2

      YAML

      expect(result.value).to eq(expected_yaml)
    end
  end


  describe "load_yaml builtin" do
    let(:yaml_content) do
      <<~YAML
        test_data:
          name: "Test"
          value: 42
          nested:
            flag: true
      YAML
    end

    before do
      File.write("/tmp/test.yml", yaml_content)
    end

    after do
      FileUtils.rm("/tmp/test.yml")
    end

    it "loads YAML files as objects" do
      result = Aua.run('load_yaml("/tmp/test.yml")')
      expect(result).to be_a(Aua::Dict)
      expect(result.values["test_data"]).to be_a(Aua::Dict)
      expect(result.values["test_data"].values["name"].value).to eq("Test")
      expect(result.values["test_data"].values["value"].value).to eq(42)
      expect(result.values["test_data"].values["nested"].values["flag"].value).to eq(true)
    end

    it "returns nihil for non-existent file" do
      result = Aua.run('load_yaml("/nonexistent.yml")')
      expect(result).to be_a(Aua::Nihil)
    end
  end
end
