module NoSE
  module CLI
    # Add a command to load index data into a backend from a configured loader
    class NoSECLI < Thor
      desc 'load PLAN_FILE_OR_SCHEMA',
           'create indexes from the given PLAN_FILE_OR_SCHEMA'

      long_desc <<-LONGDESC
        `nose load` will load a schema either from generated plan file from
        `nose search` or a named schema in the `schemas` directory. It will
        then populate the backend indexes as defined by the schema using data
        from the configured loader. It assumes that the indexes have already
        been created by `nose create`.
      LONGDESC

      option :progress, type: :boolean, default: true, aliases: '-p',
                        desc: 'whether to display an indication of progress'
      option :limit, type: :numeric, default: nil, aliases: '-l',
                     desc: 'limit the number of entries loaded ' \
                           '(useful for testing)'
      option :skip_nonempty, type: :boolean, default: true, aliases: '-s',
                             desc: 'ignore indexes which are not empty'

      def load(*plan_files)
        plan_files.each do |plan_file|
          result, backend = load_plans plan_file, options

          # Create a new instance of the loader class
          loader_class = get_class 'loader', options
          loader = loader_class.new result.workload, backend

          # Remove the name from the options and execute the loader
          loader.load result.indexes, options[:loader], options[:progress],
                      options[:limit], options[:skip_nonempty]
        end
      end
    end
  end
end
