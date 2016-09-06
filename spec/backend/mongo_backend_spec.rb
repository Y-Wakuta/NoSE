require 'nose/backend/mongo'

module NoSE
  module Backend
    describe MongoBackend do
      include_examples 'backend processing', mongo: true do
        let(:config) do
          {
            name: 'mongo',
            uri: 'mongodb://localhost:27017/',
            database: 'nose'
          }
        end

        let(:backend) do
          MongoBackend.new plans.schema.model, plans.schema.indexes.values,
                           [], [], config
        end
      end
    end
  end
end
