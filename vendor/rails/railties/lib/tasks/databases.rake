namespace :db do
  namespace :create do
    desc 'Create all the local databases defined in config/database.yml'
    task :all => :environment do
      ActiveRecord::Base.configurations.each_value do |config|
        # Skip entries that don't have a database key, such as the first entry here:
        #
        #  defaults: &defaults
        #    adapter: mysql
        #    username: root
        #    password:
        #    host: localhost
        #
        #  development:
        #    database: blog_development
        #    <<: *defaults
        next unless config['database']
        # Only connect to local databases
        if %w( 127.0.0.1 localhost ).include?(config['host']) || config['host'].blank?
          create_database(config)
        else
          p "This task only creates local databases. #{config['database']} is on a remote host."
        end
      end
    end
  end

  desc 'Create the database defined in config/database.yml for the current RAILS_ENV'
  task :create => :environment do
    create_database(ActiveRecord::Base.configurations[RAILS_ENV])
  end

  def create_database(config)
    begin
      ActiveRecord::Base.establish_connection(config)
      ActiveRecord::Base.connection
    rescue
      case config['adapter']
      when 'mysql'
        @charset   = ENV['CHARSET']   || 'utf8'
        @collation = ENV['COLLATION'] || 'utf8_general_ci'
        begin
          ActiveRecord::Base.establish_connection(config.merge({'database' => nil}))
          ActiveRecord::Base.connection.create_database(config['database'], {:charset => @charset, :collation => @collation})
          ActiveRecord::Base.establish_connection(config)
        rescue
          $stderr.puts "Couldn't create database for #{config.inspect}"
        end
      when 'postgresql'
        `createdb "#{config['database']}" -E utf8`
      when 'sqlite'
        `sqlite "#{config['database']}"`
      when 'sqlite3'
        `sqlite3 "#{config['database']}"`
      end
    else
      p "#{config['database']} already exists"
    end
  end

  namespace :drop do
    desc 'Drops all the local databases defined in config/database.yml'
    task :all => :environment do
      ActiveRecord::Base.configurations.each_value do |config|
        # Skip entries that don't have a database key
        next unless config['database']
        # Only connect to local databases
        if config['host'] == 'localhost' || config['host'].blank?
          drop_database(config)
        else
          p "This task only drops local databases. #{config['database']} is on a remote host."
        end
      end
    end
  end

  desc 'Drops the database for the current RAILS_ENV'
  task :drop => :environment do
    drop_database(ActiveRecord::Base.configurations[RAILS_ENV || 'development'])
  end

  desc "Migrate the database through scripts in db/migrate. Target specific version with VERSION=x. Turn off output with VERBOSE=false."
  task :migrate => :environment do
    ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
    ActiveRecord::Migrator.migrate("db/migrate/", ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
    Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
  end

  namespace :migrate do
    desc  'Rollbacks the database one migration and re migrate up. If you want to rollback more than one step, define STEP=x'
    task :redo => [ 'db:rollback', 'db:migrate' ]

    desc 'Resets your database using your migrations for the current environment'
    task :reset => ["db:drop", "db:create", "db:migrate"]
  end

  desc 'Rolls the schema back to the previous version. Specify the number of steps with STEP=n'
  task :rollback => :environment do
    step = ENV['STEP'] ? ENV['STEP'].to_i : 1
    version = ActiveRecord::Migrator.current_version - step
    ActiveRecord::Migrator.migrate('db/migrate/', version)
  end

  desc 'Drops and recreates the database from db/schema.rb for the current environment.'
  task :reset => ['db:drop', 'db:create', 'db:schema:load']

  desc "Retrieves the charset for the current environment's database"
  task :charset => :environment do
    config = ActiveRecord::Base.configurations[RAILS_ENV || 'development']
    case config['adapter']
    when 'mysql'
      ActiveRecord::Base.establish_connection(config)
      puts ActiveRecord::Base.connection.charset
    else
      puts 'sorry, your database adapter is not supported yet, feel free to submit a patch'
    end
  end

  desc "Retrieves the collation for the current environment's database"
  task :collation => :environment do
    config = ActiveRecord::Base.configurations[RAILS_ENV || 'development']
    case config['adapter']
    when 'mysql'
      ActiveRecord::Base.establish_connection(config)
      puts ActiveRecord::Base.connection.collation
    else
      puts 'sorry, your database adapter is not supported yet, feel free to submit a patch'
    end
  end

  desc "Retrieves the current schema version number"
  task :version => :environment do
    puts "Current version: #{ActiveRecord::Migrator.current_version}"
  end

  desc "Raises an error if there are pending migrations"
  task :abort_if_pending_migrations => :environment do
    if defined? ActiveRecord
      pending_migrations = ActiveRecord::Migrator.new(:up, 'db/migrate').pending_migrations

      if pending_migrations.any?
        puts "You have #{pending_migrations.size} pending migrations:"
        pending_migrations.each do |pending_migration|
          puts '  %4d %s' % [pending_migration.version, pending_migration.name]
        end
        abort "Run `rake db:migrate` to update your database then try again."
      end
    end
  end

  namespace :fixtures do
    desc "Load fixtures into the current environment's database.  Load specific fixtures using FIXTURES=x,y"
    task :load => :environment do
      require 'active_record/fixtures'
      ActiveRecord::Base.establish_connection(RAILS_ENV.to_sym)
      (ENV['FIXTURES'] ? ENV['FIXTURES'].split(/,/) : Dir.glob(File.join(RAILS_ROOT, 'test', 'fixtures', '*.{yml,csv}'))).each do |fixture_file|
        Fixtures.create_fixtures('test/fixtures', File.basename(fixture_file, '.*'))
      end
    end

    desc "Search for a fixture given a LABEL or ID."
    task :identify => :environment do
      require "active_record/fixtures"

      label, id = ENV["LABEL"], ENV["ID"]
      raise "LABEL or ID required" if label.blank? && id.blank?

      puts %Q(The fixture ID for "#{label}" is #{Fixtures.identify(label)}.) if label

      Dir["#{RAILS_ROOT}/test/fixtures/**/*.yml"].each do |file|
        if data = YAML::load(ERB.new(IO.read(file)).result)
          data.keys.each do |key|
            key_id = Fixtures.identify(key)

            if key == label || key_id == id.to_i
              puts "#{file}: #{key} (#{key_id})"
            end
          end
        end
      end
    end
  end

  namespace :schema do
    desc "Create a db/schema.rb file that can be portably used against any DB supported by AR"
    task :dump => :environment do
      require 'active_record/schema_dumper'
      File.open(ENV['SCHEMA'] || "db/schema.rb", "w") do |file|
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
      end
    end

    desc "Load a schema.rb file into the database"
    task :load => :environment do
      file = ENV['SCHEMA'] || "db/schema.rb"
      load(file)
    end
  end

  namespace :structure do
    desc "Dump the database structure to a SQL file"
    task :dump => :environment do
      abcs = ActiveRecord::Base.configurations
      case abcs[RAILS_ENV]["adapter"]
      when "mysql", "oci", "oracle"
        ActiveRecord::Base.establish_connection(abcs[RAILS_ENV])
        File.open("db/#{RAILS_ENV}_structure.sql", "w+") { |f| f << ActiveRecord::Base.connection.structure_dump }
      when "postgresql"
        ENV['PGHOST']     = abcs[RAILS_ENV]["host"] if abcs[RAILS_ENV]["host"]
        ENV['PGPORT']     = abcs[RAILS_ENV]["port"].to_s if abcs[RAILS_ENV]["port"]
        ENV['PGPASSWORD'] = abcs[RAILS_ENV]["password"].to_s if abcs[RAILS_ENV]["password"]
        search_path = abcs[RAILS_ENV]["schema_search_path"]
        search_path = "--schema=#{search_path}" if search_path
        `pg_dump -i -U "#{abcs[RAILS_ENV]["username"]}" -s -x -O -f db/#{RAILS_ENV}_structure.sql #{search_path} #{abcs[RAILS_ENV]["database"]}`
        raise "Error dumping database" if $?.exitstatus == 1
      when "sqlite", "sqlite3"
        dbfile = abcs[RAILS_ENV]["database"] || abcs[RAILS_ENV]["dbfile"]
        `#{abcs[RAILS_ENV]["adapter"]} #{dbfile} .schema > db/#{RAILS_ENV}_structure.sql`
      when "sqlserver"
        `scptxfr /s #{abcs[RAILS_ENV]["host"]} /d #{abcs[RAILS_ENV]["database"]} /I /f db\\#{RAILS_ENV}_structure.sql /q /A /r`
        `scptxfr /s #{abcs[RAILS_ENV]["host"]} /d #{abcs[RAILS_ENV]["database"]} /I /F db\ /q /A /r`
      when "firebird"
        set_firebird_env(abcs[RAILS_ENV])
        db_string = firebird_db_string(abcs[RAILS_ENV])
        sh "isql -a #{db_string} > db/#{RAILS_ENV}_structure.sql"
      else
        raise "Task not supported by '#{abcs["test"]["adapter"]}'"
      end

      if ActiveRecord::Base.connection.supports_migrations?
        File.open("db/#{RAILS_ENV}_structure.sql", "a") { |f| f << ActiveRecord::Base.connection.dump_schema_information }
      end
    end
  end

  namespace :test do
    desc "Recreate the test database from the current environment's database schema"
    task :clone => %w(db:schema:dump db:test:purge) do
      ActiveRecord::Base.establish_connection(ActiveRecord::Base.configurations['test'])
      ActiveRecord::Schema.verbose = false
      Rake::Task["db:schema:load"].invoke
    end


    desc "Recreate the test databases from the development structure"
    task :clone_structure => [ "db:structure:dump", "db:test:purge" ] do
      abcs = ActiveRecord::Base.configurations
      case abcs["test"]["adapter"]
      when "mysql"
        ActiveRecord::Base.establish_connection(:test)
        ActiveRecord::Base.connection.execute('SET foreign_key_checks = 0')
        IO.readlines("db/#{RAILS_ENV}_structure.sql").join.split("\n\n").each do |table|
          ActiveRecord::Base.connection.execute(table)
        end
      when "postgresql"
        ENV['PGHOST']     = abcs["test"]["host"] if abcs["test"]["host"]
        ENV['PGPORT']     = abcs["test"]["port"].to_s if abcs["test"]["port"]
        ENV['PGPASSWORD'] = abcs["test"]["password"].to_s if abcs["test"]["password"]
        `psql -U "#{abcs["test"]["username"]}" -f db/#{RAILS_ENV}_structure.sql #{abcs["test"]["database"]}`
      when "sqlite", "sqlite3"
        dbfile = abcs["test"]["database"] || abcs["test"]["dbfile"]
        `#{abcs["test"]["adapter"]} #{dbfile} < db/#{RAILS_ENV}_structure.sql`
      when "sqlserver"
        `osql -E -S #{abcs["test"]["host"]} -d #{abcs["test"]["database"]} -i db\\#{RAILS_ENV}_structure.sql`
      when "oci", "oracle"
        ActiveRecord::Base.establish_connection(:test)
        IO.readlines("db/#{RAILS_ENV}_structure.sql").join.split(";\n\n").each do |ddl|
          ActiveRecord::Base.connection.execute(ddl)
        end
      when "firebird"
        set_firebird_env(abcs["test"])
        db_string = firebird_db_string(abcs["test"])
        sh "isql -i db/#{RAILS_ENV}_structure.sql #{db_string}"
      else
        raise "Task not supported by '#{abcs["test"]["adapter"]}'"
      end
    end

    desc "Empty the test database"
    task :purge => :environment do
      abcs = ActiveRecord::Base.configurations
      case abcs["test"]["adapter"]
      when "mysql"
        ActiveRecord::Base.establish_connection(:test)
        ActiveRecord::Base.connection.recreate_database(abcs["test"]["database"])
      when "postgresql"
        ENV['PGHOST']     = abcs["test"]["host"] if abcs["test"]["host"]
        ENV['PGPORT']     = abcs["test"]["port"].to_s if abcs["test"]["port"]
        ENV['PGPASSWORD'] = abcs["test"]["password"].to_s if abcs["test"]["password"]
        enc_option = "-E #{abcs["test"]["encoding"]}" if abcs["test"]["encoding"]

        ActiveRecord::Base.clear_active_connections!
        `dropdb -U "#{abcs["test"]["username"]}" #{abcs["test"]["database"]}`
        `createdb #{enc_option} -U "#{abcs["test"]["username"]}" #{abcs["test"]["database"]}`
      when "sqlite","sqlite3"
        dbfile = abcs["test"]["database"] || abcs["test"]["dbfile"]
        File.delete(dbfile) if File.exist?(dbfile)
      when "sqlserver"
        dropfkscript = "#{abcs["test"]["host"]}.#{abcs["test"]["database"]}.DP1".gsub(/\\/,'-')
        `osql -E -S #{abcs["test"]["host"]} -d #{abcs["test"]["database"]} -i db\\#{dropfkscript}`
        `osql -E -S #{abcs["test"]["host"]} -d #{abcs["test"]["database"]} -i db\\#{RAILS_ENV}_structure.sql`
      when "oci", "oracle"
        ActiveRecord::Base.establish_connection(:test)
        ActiveRecord::Base.connection.structure_drop.split(";\n\n").each do |ddl|
          ActiveRecord::Base.connection.execute(ddl)
        end
      when "firebird"
        ActiveRecord::Base.establish_connection(:test)
        ActiveRecord::Base.connection.recreate_database!
      else
        raise "Task not supported by '#{abcs["test"]["adapter"]}'"
      end
    end

    desc 'Prepare the test database and load the schema'
    task :prepare => %w(environment db:abort_if_pending_migrations) do
      if defined?(ActiveRecord) && !ActiveRecord::Base.configurations.blank?
        Rake::Task[{ :sql  => "db:test:clone_structure", :ruby => "db:test:clone" }[ActiveRecord::Base.schema_format]].invoke
      end
    end
  end

  namespace :sessions do
    desc "Creates a sessions migration for use with CGI::Session::ActiveRecordStore"
    task :create => :environment do
      raise "Task unavailable to this database (no migration support)" unless ActiveRecord::Base.connection.supports_migrations?
      require 'rails_generator'
      require 'rails_generator/scripts/generate'
      Rails::Generator::Scripts::Generate.new.run(["session_migration", ENV["MIGRATION"] || "CreateSessions"])
    end

    desc "Clear the sessions table"
    task :clear => :environment do
      session_table = 'session'
      session_table = Inflector.pluralize(session_table) if ActiveRecord::Base.pluralize_table_names
      ActiveRecord::Base.connection.execute "DELETE FROM #{session_table}"
    end
  end
end

def drop_database(config)
  case config['adapter']
  when 'mysql'
    ActiveRecord::Base.connection.drop_database config['database']
  when /^sqlite/
    FileUtils.rm_f(File.join(RAILS_ROOT, config['database']))
  when 'postgresql'
    `dropdb "#{config['database']}"`
  end
end

def session_table_name
  ActiveRecord::Base.pluralize_table_names ? :sessions : :session
end

def set_firebird_env(config)
  ENV["ISC_USER"]     = config["username"].to_s if config["username"]
  ENV["ISC_PASSWORD"] = config["password"].to_s if config["password"]
end

def firebird_db_string(config)
  FireRuby::Database.db_string_for(config.symbolize_keys)
end
