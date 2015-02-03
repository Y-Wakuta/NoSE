require 'nose/loader/csv'

require 'fakefs/spec_helpers'

module NoSE::Loader
  describe CsvLoader do
    include_context 'entities'
    include FakeFS::SpecHelpers

    before(:each) do
      FileUtils.mkdir_p '/tmp/csv'

      File.open '/tmp/csv/User.csv', 'w' do |file|
        file.puts <<-EOF.gsub(/^ {8}/, '')
        UserId,Username,City
        1,Alice,Chicago
        EOF
      end
    end

    it 'can load data into a backend' do
      backend = instance_spy NoSE::Backend::BackendBase

      index = NoSE::Index.new [user['City']], [], [user['Username']], [user]
      loader = CsvLoader.new workload, backend
      loader.load([index], {directory: '/tmp/csv'})

      expect(backend).to have_received(:index_insert_chunk).with(
        index,
        [{'User_UserId' => '1', 'User_Username' => 'Alice', 'User_City' => 'Chicago'}])
    end
  end
end