module NoSE
  # A representation of an insert in the workload
  class Insert < Statement
    include StatementConditions
    include StatementSettings
    include StatementSupportQuery

    def initialize(params, text, group: nil, label: nil)
      super params, text, group: group, label: label

      @settings = params[:settings]
      fail InvalidStatementException, 'Must insert primary key' \
        unless @settings.map(&:field).include?(entity.id_field)

      populate_conditions params
    end

    # Build a new insert from a provided parse tree
    # @return [Insert]
    def self.parse(tree, params, text, group: nil, label: nil)
      settings_from_tree tree, params
      conditions_from_tree tree, params

      Insert.new params, text, group: group, label: label
    end

    # Extract conditions from a parse tree
    # @return [Hash]
    def self.conditions_from_tree(tree, params)
      connections = tree[:connections] || []
      connections = connections.map do |connection|
        field = params[:entity][connection[:target].to_s]
        value = connection[:target_pk]

        type = field.class.const_get 'TYPE'
        value = field.class.value_from_string(value.to_s) \
          unless type.nil? || value.nil?

        connection.delete :value
        Condition.new field, :'=', value
      end

      params[:conditions] = Hash[connections.map do |connection|
        [connection.field.id, connection]
      end]
    end
    private_class_method :conditions_from_tree

    # Produce the SQL text corresponding to this insert
    # @return [String]
    def unparse
      insert = "INSERT INTO #{entity.name} "
      insert += settings_clause

      insert += ' AND CONNECT TO ' + @conditions.values.map do |condition|
        value = maybe_quote condition.value, condition.field
        "#{condition.field.name}(#{value})"
      end.join(', ') unless @conditions.empty?

      insert
    end

    def ==(other)
      other.is_a?(Insert) &&
        @graph == other.graph &&
        entity == other.entity &&
        @settings == other.settings &&
        @conditions == other.conditions
    end
    alias eql? ==

    def hash
      @hash ||= [@graph, entity, @settings, @conditions].hash
    end

    # Determine if this insert modifies an index
    def modifies_index?(index)
      return true if modifies_single_entity_index?(index)
      return false if index.path.length == 1
      return false unless index.path.entities.include? entity

      # Check if the index crosses any of the connection keys
      keys = @conditions.each_value.map(&:field)
      keys += keys.map(&:reverse)

      # We must be connecting on some component of the path
      # if the index is going to be modified by this insertion
      keys.count { |key| index.path.include?(key) } > 0
    end

    # Specifies that inserts require insertion
    def requires_insert?(_index)
      true
    end

    # Get the where clause for a support query over the given path
    # @return [String]
    def support_query_condition_for_path(keys, path)
      'WHERE ' + path.entries.map do |key|
        if keys.include?(key) ||
           (key.is_a?(Fields::ForeignKeyField) &&
            path.entities.include?(key.entity))
          # Find the ID for this entity in the path and include a predicate
          id = key.entity.id_field
          "#{path.find_field_parent(id).name}.#{id.name} = ?"
        elsif path.entities.map { |e| e.id_field }.include?(key)
          # Include the key for the entity being inserted
          "#{path.find_field_parent(key).name}.#{key.name} = ?"
        end
      end.compact.join(' AND ')
    end

    # Support queries are required for index insertion with connection
    # to select attributes of the other related entities
    # @return [Array<SupportQuery>]
    def support_queries(index)
      return [] unless modifies_index?(index) &&
                       !modifies_single_entity_index?(index)

      params = {}
      params[:select] = index.all_fields -
                        @settings.map(&:field).to_set -
                        @conditions.each_value.map do |condition|
                          condition.field.entity.id_field
                        end.to_set
      return [] if params[:select].empty?

      # Make a copy of the graph with only entities we need to select from
      params[:graph] = Marshal.load(Marshal.dump(index.graph))
      @conditions.each_value do |c|
        params[:graph].add_edge c.field.parent, c.field.entity, c.field
      end
      params[:graph].remove_nodes params[:graph].entities -
                                  params[:select].map(&:parent).to_set

      params[:key_path] = params[:graph].longest_path
      params[:entity] = params[:key_path].first.parent

      # Build conditions by traversing the foreign keys
      conditions = @conditions.each_value.map do |c|
        next unless params[:graph].entities.include? c.field.entity

        Condition.new c.field.entity.id_field, c.operator, c.value
      end.compact
      params[:conditions] = Hash[conditions.map do |condition|
        [condition.field.id, condition]
      end]

      support_query = SupportQuery.new params, nil, group: @group
      support_query.instance_variable_set :@statement, self
      support_query.instance_variable_set :@index, index
      support_query.instance_variable_set :@comment, (hash ^ index.hash).to_s
      support_query.hash
      support_query.freeze

      [support_query]
    end

    # The settings fields are provided with the insertion
    def given_fields
      @settings.map(&:field) + @conditions.each_value.map do |condition|
        condition.field.entity.id_field
      end
    end

    private

    # Check if the insert modifies a single entity index
    # @return [Boolean]
    def modifies_single_entity_index?(index)
      !(@settings.map(&:field).to_set & index.all_fields).empty? &&
        index.path.length == 1 && index.path.first.parent == entity
    end
  end
end